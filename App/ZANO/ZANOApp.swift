import Foundation
import SwiftUI
import SwiftData
import Core

@main
struct ZANOApp: App {
    init() {
        // docs/spec.md §23 "Instrument from day one": wire analytics/crash reporting at launch so
        // every later session's screen views, intents, unlock kinds, and shield impressions have
        // somewhere to land from day one instead of being retrofitted in later.
        //
        // Neither SPM package is added to project.yml yet (see docs/dependencies.md, Session 1),
        // so each block below is guarded with `#if canImport` — it compiles out entirely today
        // and starts running with no code changes once the package is linked. `Analytics.setup`
        // / `CrashReporting.setup` are themselves also no-ops without their SDK linked; the guard
        // here is belt-and-suspenders so this file never depends on either package existing.
        #if canImport(PostHog)
        Analytics.shared.setup(
            apiKey: Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? "",
            host: (Bundle.main.object(forInfoDictionaryKey: "POSTHOG_HOST") as? String)
                .flatMap(URL.init(string:)) ?? URL(string: "https://us.i.posthog.com")!
        )
        #endif

        #if canImport(Sentry)
        CrashReporting.shared.setup(
            dsn: Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
        )
        #endif

        // TODO(cross-module, Session 1): once the PostHog/Sentry accounts exist and the SPM
        // packages are added to project.yml (docs/PROGRESS.md currently lists both "Not
        // created"), add `POSTHOG_API_KEY` / `POSTHOG_HOST` / `SENTRY_DSN` to project.yml's
        // ZANO target Info.plist properties. Until real values are present there, both `setup`
        // calls above no-op on the empty string `Bundle.main` returns.

        // docs/spec.md §11 data flow: "every user action → App Intent → Core → SwiftData (App
        // Group) → widgets/shield read state instantly → Sync outbox pushes to Supabase when
        // online". `SyncEngine` is an actor (`Core/Sources/Core/Sync/SyncEngine.swift`) and must
        // be configured "once, as early as possible during app/extension launch" per its own doc
        // comment, before anything calls `enqueue` — `init()` itself can't be async, so this
        // fires the one-time configuration from a detached launch task instead. No `SyncBackend`
        // is supplied yet (Session 7, `feat/backend`, owns that); `enqueue` works without one and
        // only `flush()` needs it, so outbox rows queue safely from day one and start actually
        // pushing the moment Session 7 calls `SyncEngine.shared.setBackend(_:)`.
        Task {
            await SyncEngine.shared.configure(modelContainer: ModelContainer.appGroup)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // The one shared App Group SwiftData store (docs/spec.md §11/§13; `Core/Sources/Core/
        // Store/ModelContainer+AppGroup.swift`) — attached here so every view in the hierarchy
        // gets a working `\.modelContext`/`@Query` for free, instead of each Feature screen
        // reaching for `ModelContainer.appGroup` individually. `ModelContainer.appGroup` never
        // throws (it falls back to an in-memory container and logs a `.fault` if the App Group
        // entitlement is misconfigured — see that file's doc comment) so there is no `throws`/
        // `try?` to handle at this call site.
        .modelContainer(ModelContainer.appGroup)
    }
}
