// LockedOutMomentView.swift
// App / ZANO / Features / Share
//
// docs/spec.md §5.16 "Locked-Out Moment": "When a user tries to open a blocked app 3+ times in an
// hour, the shield shows a special 'Locked Out' card with a 'Share this' option ('My phone won't
// let me open TikTok until I hit the gym'). Turns friction into content." Also implements the
// "3+ attempts in an hour" counter this moment is triggered by (this task's brief: "triggered by a
// 3-attempts-in-an-hour counter you implement here").
//
// Renders through `LockedOutPoster` (`SharePoster.swift`, this folder): a fixed 360 x 640pt canvas
// exported at scale 3 (= 1080 x 1920 px), with the on-screen preview being the same view scaled to
// fit, so what the user approves is what they post. This replaces the old `ShareCard` path — three
// lines of 22pt text on a gradient with no graphic, exported at a UI-sized type ramp on a 1080pt
// canvas (see `SharePoster.swift`'s header). The poster's hero is the spec's own line ("My phone
// won't let me open TikTok until I hit the gym.") as display type over a lock medallion, with the
// attempt count as a stat pill: `one sec`'s finding is that showing how often you tried is what
// changes behavior (`docs/design/competitive-research.md` 3.3).
//
// Copy: `Copy.lockedOut.*` and `Copy.share.*` (`Core/Sources/Core/Copy/ShareCopy.swift`). This file
// composes no user-facing string of its own: the app-name and goal-summary fallbacks live in
// `Copy.lockedOut.headline`, which owns the "This app" wording the same way `ShieldCopy.content(for:)`
// owns its own `shieldedName` fallback.
//
// CROSS-MODULE GAP (flagging, not guessing): the only place iOS actually tells us "the user just
// tried to open a blocked app" is `ShieldConfigurationExtension.configuration(shielding:...)`
// (`Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift`, owned by another session, not
// touched here) — the system calls one of those four overrides every single time the shield renders.
// `ManagedSettingsUI` gives no other "an attempt happened" callback (`ShieldActionDelegate` only fires
// on an explicit button tap). That means the counter's *write* side must be reachable from an
// extension target, which per CLAUDE.md ("Shared code goes ONLY in Core/Sources/Core/<Module>...
// Extension-only code in Extensions/<Name>/") means it has to live in Core — but this task's
// owned-file list is only the files in this folder, all in the `ZANO` **app** target, which
// `ZANOShieldConfig` cannot import. So:
//   `LockedOutAttemptTracker` below is written to have ZERO app-target dependencies (only
//   `Foundation` + `Core`'s public `AppGroup.identifier`) specifically so it can be relocated
//   verbatim into `Core/Sources/Core/Verification/LockedOutAttemptTracker.swift` by whoever owns
//   that extension file — at that point `ShieldConfigurationExtension` should call
//   `LockedOutAttemptTracker.recordAttempt(appName:)` once per `configuration(shielding:...)` call
//   (right alongside its existing `SharedDefaults` reads) and this view starts reflecting real
//   attempts with no other change needed here. Until that move happens, this type still works
//   correctly for any in-app caller (previews, tests, or a future notification-tap path) — it just
//   isn't yet fed real shield-render events. This is exactly the same shape of gap
//   `ShieldCopy.ShieldContext.recentMiss` already documents for `neverMissTwiceArmed` — a fully-
//   built consumer waiting on one producer wire-up outside this task's scope.

import Foundation
import SwiftUI
import Core

// MARK: - Attempt tracking (spec §5.16: "3+ times in an hour")

/// Counts "tried to open a blocked app" events in a trailing 60-minute window and decides when
/// that crosses spec §5.16's threshold. See this file's header for why this type deliberately has
/// no dependency on anything but `Foundation` and `Core.AppGroup` — it's written to be liftable
/// into `Core/Sources/Core/Verification` verbatim once an extension needs to call `recordAttempt`.
///
/// Storage: its own namespaced keys in the same App Group `UserDefaults` suite `SharedDefaults`
/// (`Core/Sources/Core/Store/SharedDefaults.swift`) uses, but declared independently here rather
/// than added to that file — `SharedDefaults.swift` isn't in this task's owned-file list, and a
/// second, narrowly-scoped reader/writer of the *same suite* with its own keys can't collide with
/// it (UserDefaults keys are just strings; these are prefixed distinctly below).
public enum LockedOutAttemptTracker {

    /// spec §5.16: "3+ times in an hour."
    public static let threshold = 3
    /// spec §5.16: "in an hour."
    public static let window: TimeInterval = 3600

    /// `UserDefaults` is documented thread-safe by Apple but the stock SDK doesn't mark the class
    /// `Sendable` as of this writing — same rationale, same annotation, as `SharedDefaults.swift`.
    nonisolated(unsafe) private static let suite: UserDefaults =
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    private enum Keys {
        static let attemptTimestamps = "shared.lockedOutMoment.attemptTimestamps"
        static let lastTriggeredAt = "shared.lockedOutMoment.lastTriggeredAt"
    }

    /// Records one "the user tried to open a blocked app" event and returns a
    /// ``LockedOutMomentTrigger`` the moment this crosses the spec §5.16 threshold — `nil` on every
    /// call that doesn't (either the trailing-hour count is still under ``threshold``, or it's
    /// already been surfaced once for this window; see the debounce note below).
    ///
    /// Debounce: once triggered, this won't trigger again for a full ``window`` even though the
    /// trailing count stays at or above ``threshold`` on every subsequent attempt within that same
    /// hour — without this, a user who keeps trying the same locked app would get the Locked-Out
    /// card shoved at them on attempt 4, 5, 6... which turns a fun, shareable moment into a nag.
    /// One prompt per qualifying hour matches spec §8 rule 7's broader "nudge scarcity" spirit even
    /// though this isn't a push notification.
    ///
    /// - Parameters:
    ///   - appName: Localized display name of the app/site the user just tried to open, when the
    ///     call site has one (e.g. `Application.localizedDisplayName` / `WebDomain.domain` from a
    ///     `ShieldConfigurationDataSource` override). `nil` for a category-level shield with no
    ///     single name to report.
    ///   - date: Injectable for deterministic tests/previews. Defaults to `.now`.
    @discardableResult
    public static func recordAttempt(appName: String?, at date: Date = .now) -> LockedOutMomentTrigger? {
        var timestamps = storedTimestamps()
        timestamps.append(date)
        timestamps = timestamps.filter { date.timeIntervalSince($0) <= window }
        setStoredTimestamps(timestamps)

        guard timestamps.count >= threshold else { return nil }

        if let lastTriggeredAt = suite.object(forKey: Keys.lastTriggeredAt) as? Date,
           date.timeIntervalSince(lastTriggeredAt) < window {
            return nil
        }
        suite.set(date, forKey: Keys.lastTriggeredAt)

        return LockedOutMomentTrigger(
            appName: appName,
            attemptCount: timestamps.count,
            windowStart: timestamps.first ?? date,
            triggeredAt: date
        )
    }

    /// How many attempts are currently within the trailing ``window`` — for a caller that wants to
    /// poll state (e.g. show a badge) without itself recording a new attempt.
    public static func currentAttemptCount(asOf date: Date = .now) -> Int {
        storedTimestamps().filter { date.timeIntervalSince($0) <= window }.count
    }

    /// Clears all recorded attempts and the trigger debounce. For previews/tests only — nothing in
    /// the app or an extension should call this during normal operation.
    public static func reset() {
        suite.removeObject(forKey: Keys.attemptTimestamps)
        suite.removeObject(forKey: Keys.lastTriggeredAt)
    }

    private static func storedTimestamps() -> [Date] {
        (suite.array(forKey: Keys.attemptTimestamps) as? [Date]) ?? []
    }

    private static func setStoredTimestamps(_ timestamps: [Date]) {
        suite.set(timestamps, forKey: Keys.attemptTimestamps)
    }
}

/// One qualifying "3+ attempts in an hour" crossing, as returned by
/// ``LockedOutAttemptTracker/recordAttempt(appName:at:)``.
public struct LockedOutMomentTrigger: Sendable, Equatable {
    public let appName: String?
    public let attemptCount: Int
    public let windowStart: Date
    public let triggeredAt: Date

    public init(appName: String?, attemptCount: Int, windowStart: Date, triggeredAt: Date) {
        self.appName = appName
        self.attemptCount = attemptCount
        self.windowStart = windowStart
        self.triggeredAt = triggeredAt
    }
}

// MARK: - Content

/// Everything `LockedOutMomentView` needs, fully caller-composed — same philosophy `ShareCard`/
/// `RecapCard` already use (a plain `Sendable` value, no SwiftData/App-Group read of its own) so
/// this view stays trivially previewable and reusable regardless of *how* the caller learned a
/// trigger fired (a live ``LockedOutAttemptTracker`` crossing today; a future push-driven re-open
/// tomorrow).
public struct LockedOutMomentContent: Sendable, Equatable {
    /// Display name of the app the user kept trying to open (e.g. `"TikTok"`). `nil` for a
    /// category-level shield with no single app name to report — `Copy.lockedOut.headline(appName:
    /// blockingGoalSummary:)` owns the "This app" fallback wording for that case (mirroring
    /// `ShieldCopy.content(for:)`'s identical `shieldedName` fallback), not this view.
    public let appName: String?
    public let attemptCount: Int
    public let windowMinutes: Int
    /// Caller-composed short phrase for what unlocks it (e.g. `"hit the gym"`), already resolved
    /// from whichever goal is blocking — this view has no goal knowledge of its own. `nil` when the
    /// caller doesn't have one to hand (e.g. multiple required goals with no single headline one).
    public let blockingGoalSummary: String?
    public let goalsRemaining: Int?
    public let streak: Int?

    public init(
        appName: String?,
        attemptCount: Int,
        windowMinutes: Int = Int(LockedOutAttemptTracker.window / 60),
        blockingGoalSummary: String? = nil,
        goalsRemaining: Int? = nil,
        streak: Int? = nil
    ) {
        self.appName = appName
        self.attemptCount = attemptCount
        self.windowMinutes = windowMinutes
        self.blockingGoalSummary = blockingGoalSummary
        self.goalsRemaining = goalsRemaining
        self.streak = streak
    }

    /// Bridges a live ``LockedOutAttemptTracker`` crossing into displayable content. The tracker
    /// itself has no goal/streak knowledge (see this file's header — it's deliberately dependency-
    /// free so it can move into Core), so the caller supplies those from whatever it already has on
    /// screen (e.g. `SharedDefaults.goalsRemainingForActiveLock` / `.currentStreak`, or a live
    /// `Streak`/`Goal` `@Query`).
    public static func from(
        _ trigger: LockedOutMomentTrigger,
        blockingGoalSummary: String? = nil,
        goalsRemaining: Int? = nil,
        streak: Int? = nil
    ) -> LockedOutMomentContent {
        LockedOutMomentContent(
            // Passed through as-is (never resolved to a literal "This app" here) — `Copy.lockedOut.
            // headline(appName:blockingGoalSummary:)` owns that fallback wording, the same way
            // `ShieldCopy.content(for:)` owns its own identical `shieldedName` fallback. CLAUDE.md
            // reserves user-facing copy for Core/Sources/Core/Copy; this view only ever passes
            // through what `LockedOutAttemptTracker` actually reported.
            appName: trigger.appName,
            attemptCount: trigger.attemptCount,
            blockingGoalSummary: blockingGoalSummary,
            goalsRemaining: goalsRemaining,
            streak: streak
        )
    }
}

// MARK: - View

/// The Locked-Out Moment (spec §5.16): a dismissable poster, presented once
/// ``LockedOutAttemptTracker`` (or an equivalent future signal) fires, offering a "Share this"
/// export of the moment. This view never itself locks or shields anything — it's a promotional/
/// content moment layered on top of a shield that's already active, so CLAUDE.md's "any lock/shield
/// feature must always keep an emergency-unlock path" doesn't create a new obligation here (there's
/// no new lock state to escape); it's still always dismissable via `onDismiss` (the header's close
/// control, a 44pt target), as good practice for any full-screen moment.
///
/// Layout: a header carrying only the dismiss control (the poster's own eyebrow is the title), the
/// poster preview filling the space between, and the acknowledgement line plus the share action
/// pinned in a bottom bar, so the share button is on screen at every phone height and the poster
/// shrinks to fit instead of scrolling under it.
public struct LockedOutMomentView: View {
    private let content: LockedOutMomentContent
    private let onDismiss: () -> Void

    @State private var renderedImage: UIImage?
    /// `true` once the poster render has returned `nil` — see the `.task` below and
    /// `docs/design/ui-stress-test-findings.md` §3.6. Without a branch on this case, a render failure
    /// (low memory) would leave the action stuck on "Preparing…" forever, indistinguishable from
    /// "still working."
    @State private var shareRenderFailed = false
    /// Bumped by `retryShareRender()` to re-run the `.task(id:)` below on demand — a plain `.task`
    /// only fires once per this view's identity, so retrying after a failure needs an explicit id
    /// change, not just resetting the `@State` it reads.
    @State private var renderAttempt = 0
    /// Drives the poster's one-shot entrance reveal below — see `body`'s `.onAppear`. Applied only to
    /// the on-screen preview instance: the poster `SharePosterRenderer` rasterizes is a separate,
    /// untransformed instance, so an animation can never be mid-flight when it is captured
    /// (`docs/design/animation-opportunities.md` row 10's explicit constraint).
    @State private var cardAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - content: Fully-composed display data — see ``LockedOutMomentContent``.
    ///   - onDismiss: Called when the user closes this moment without sharing (or after sharing).
    public init(content: LockedOutMomentContent, onDismiss: @escaping () -> Void) {
        self.content = content
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // No title: the poster's own eyebrow ("Locked out") already is one, and repeating it
            // above the poster said the same words twice. The dismiss label stays the spec's "Not now".
            ShareMomentHeader(
                title: nil,
                dismissLabel: Copy.lockedOut.dismissButtonTitle,
                onDismiss: onDismiss
            )

            SharePosterPreview(poster: poster)
                .scaleEffect(reduceMotion || cardAppeared ? 1 : 0.92)
                .opacity(cardAppeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zanoBackdrop()
        .zanoActionBar {
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.lockedOut.acknowledgementLine)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
        .task(id: renderAttempt) {
            guard renderedImage == nil else { return }
            shareRenderFailed = false
            // `await`, not a direct call: `SharePosterRenderer.image` is `@MainActor`-isolated, and
            // this environment has no Mac/Swift compiler to confirm whether SwiftUI's `.task`
            // closure is itself MainActor-isolated on the SDK this project targets. `await` is
            // correct either way — a redundant `await` on an already-isolated call compiles fine,
            // while omitting a *required* one is a hard error.
            if let image = await SharePosterRenderer.image(of: poster) {
                renderedImage = image
            } else {
                shareRenderFailed = true
            }
        }
        // The poster's one-shot arrival, per docs/design/animation-opportunities.md row 10: scale
        // 0.92→1.0 + fade in, a `springStandard`-family spring, fired once on appear. This moment is
        // this screen's own emotional beat (spec §5.16: "turn friction into content"), so it's worth
        // the same reveal `WeeklyRecapShareView.swift` gives its poster. Reduce Motion: opacity-only,
        // no scale.
        .onAppear {
            guard !cardAppeared else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.8)) {
                cardAppeared = true
            }
        }
        // `Theme.swift`'s own header: this is a fixed, dark-only design system — see
        // `docs/design/ui-stress-test-findings.md` §2.1, and `LockSetupView.swift`'s identical
        // comment for the full rationale.
        .preferredColorScheme(.dark)
    }

    private func retryShareRender() {
        renderedImage = nil
        shareRenderFailed = false
        renderAttempt += 1
    }

    // MARK: - Actions (share / retry)

    @ViewBuilder
    private var actions: some View {
        // The "Preparing…" state crossfades into the real Share control the moment the render
        // finishes. Keyed on a small `Equatable` state enum, not the image itself: `UIImage` isn't
        // `Equatable`, which `.animation(_:value:)` requires.
        Group {
            switch shareRenderState {
            case .ready:
                if let renderedImage {
                    ShareLink(
                        item: Image(uiImage: renderedImage),
                        preview: SharePreview(
                            Copy.lockedOut.headline(appName: content.appName, blockingGoalSummary: content.blockingGoalSummary),
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        ShareActionLabel(state: .ready)
                    }
                    .buttonStyle(.pressable)
                    .transition(shareControlTransition)
                }
            case .failed:
                // A terminal failure state with its own message and a tap-to-retry affordance instead
                // of an indefinite spinner. See `docs/design/ui-stress-test-findings.md` §3.6.
                Button(action: retryShareRender) {
                    ShareActionLabel(state: .failed)
                }
                .buttonStyle(.pressable)
                .transition(shareControlTransition)
            case .preparing:
                ShareActionLabel(state: .preparing)
                    .transition(shareControlTransition)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard,
            value: shareRenderState
        )
    }

    private var shareRenderState: ShareRenderState {
        if renderedImage != nil { return .ready }
        if shareRenderFailed { return .failed }
        return .preparing
    }

    /// Reduce Motion: plain fade, no scale — same pattern as the poster reveal above.
    private var shareControlTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
    }

    // MARK: - Poster

    private var poster: LockedOutPoster {
        LockedOutPoster(
            eyebrow: Copy.lockedOut.screenTitle,
            headline: Copy.lockedOut.headline(appName: content.appName, blockingGoalSummary: content.blockingGoalSummary),
            statLine: Copy.lockedOut.statLine(attemptCount: content.attemptCount, windowMinutes: content.windowMinutes),
            highlightLine: highlightLine,
            footerLabel: Copy.share.footerWordmark
        )
    }

    private var highlightLine: String? {
        guard let goalsRemaining = content.goalsRemaining else { return nil }
        return Copy.lockedOut.highlightLine(goalsRemaining: goalsRemaining, streak: content.streak ?? 0)
    }
}

#Preview {
    LockedOutMomentView(
        content: LockedOutMomentContent(
            appName: "TikTok",
            attemptCount: 4,
            blockingGoalSummary: "hit the gym",
            goalsRemaining: 1,
            streak: 14
        ),
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
