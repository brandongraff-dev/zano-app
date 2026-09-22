// LockedOutMomentView.swift
// App / ZANO / Features / Share
//
// docs/spec.md §5.16 "Locked-Out Moment": "When a user tries to open a blocked app 3+ times in an
// hour, the shield shows a special 'Locked Out' card with a 'Share this' option ('My phone won't
// let me open TikTok until I hit the gym'). Turns friction into content." Also implements the
// "3+ attempts in an hour" counter this moment is triggered by (this task's brief: "triggered by a
// 3-attempts-in-an-hour counter you implement here").
//
// Renders through `ShareCard` (`Core/Sources/Core/UI/Components/ShareCard.swift`, docs/spec.md
// §15's core component list: "ShareCard (9:16 renderer)") rather than a bespoke layout — ShareCard
// is already the generic export surface for exactly this ("designed to be legible as a standalone
// image on Instagram/TikTok/iMessage" per its own header), and reusing it here keeps every
// shareable card in the app (this one, `WeeklyRecapShareView`) visually and technically consistent
// instead of each screen inventing its own `ImageRenderer` plumbing.
//
// docs/spec.md §15/§24 note the shield's own copy lives in `Core/Sources/Core/Copy` — this file
// follows the exact "ASSUMED API" precedent `App/ZANO/Features/LockSetup/LockSetupView.swift` and
// `App/ZANO/Features/Progress/ProgressView.swift` already set (both read in full before writing
// this file): reference `Copy.<feature>.*` by name, as if it already exists, and list every
// assumed member here so whoever implements `Core/Sources/Core/Copy` for real only has to match
// this shape. This is deliberately NOT the same tactic `TodayView.swift` used (a private in-file
// `Copy` enum) — that file predates this convention; `ProgressView`/`LockSetupView` are the more
// recent, more CLAUDE.md-compliant precedent (no hardcoded string literal ever appears at a call
// site below), so this file follows them.
//
// ASSUMED API — `Copy.lockedOut.*` / `Copy.share.*` (`Core/Sources/Core/Copy`, not owned by this
// task):
//
//   Copy.lockedOut.screenTitle: String                                          // "Locked Out"
//   Copy.lockedOut.headline(appName: String?, blockingGoalSummary: String?) -> String
//       // The spec-literal line itself, e.g. "My phone won't let me open TikTok until I hit the
//       // gym." Both parameters are caller-composed short phrases already resolved by this view —
//       // `appName` for the app the user kept trying to open, `blockingGoalSummary` for what
//       // unlocks it (e.g. "hit the gym") — and both fall back to a generic phrase when `nil`
//       // (a category-level shield has no single app name to report; multiple required goals have
//       // no single headline one), mirroring exactly how `ShieldCopy.content(for:)` (already
//       // built, `Core/Sources/Core/Copy/ShieldCopy.swift`) handles its own optional `shieldedName`
//       // with `shieldedName ?? "This app"` inline, not a separate variant table. Deliberately
//       // `String?` here, not pre-resolved to `"This app"` by this view: CLAUDE.md reserves that
//       // fallback wording for Copy to own, the same way ShieldCopy already owns it — this view
//       // only ever passes through what it actually knows.
//   Copy.lockedOut.statLine(attemptCount: Int, windowMinutes: Int) -> String     // "3 tries in the
//       // last 60 minutes"
//   Copy.lockedOut.highlightLine(goalsRemaining: Int, streak: Int) -> String     // "1 goal left ·
//       // Streak 14" — same clause style `CoachVoiceTone.goalsRemainingClause`/`streakClause`
//       // already use elsewhere, just voice-neutral since spec §5.16 gives no coach-voice example.
//   Copy.lockedOut.acknowledgementLine: String                                  // spec §5.16's own
//       // framing, e.g. "Turns friction into content. Might as well share it."
//   Copy.lockedOut.dismissButtonTitle: String                                   // "Not now"
//   Copy.share.shareButtonTitle: String                                         // spec §5.16's
//       // literal button name: "a 'Share this' option" — keep this string exactly "Share this".
//   Copy.share.preparingShareTitle: String                                      // "Preparing…"
//   Copy.share.footerWordmark: String                                          // small bottom-
//       // right logo text on every `ShareCard` export (P7 mockup, §16); shared with
//       // `WeeklyRecapShareView` so every exported card uses the same wordmark.
//
// CROSS-MODULE GAP (flagging, not guessing): the only place iOS actually tells us "the user just
// tried to open a blocked app" is `ShieldConfigurationExtension.configuration(shielding:...)`
// (`Extensions/ZANOShieldConfig/ShieldConfigurationExtension.swift`, already built by another
// session, owned by that session — not touched here) — the system calls one of those four
// overrides every single time the shield renders. `ManagedSettingsUI` gives no other "an attempt
// happened" callback (`ShieldActionDelegate` only fires on an explicit button tap). That means the
// counter's *write* side must be reachable from an extension target, which per CLAUDE.md ("Shared
// code goes ONLY in Core/Sources/Core/<Module>... Extension-only code in Extensions/<Name>/") means
// it has to live in Core — but this task's owned-file list is only the two files in this folder,
// both in the `ZANO` **app** target, which `ZANOShieldConfig` cannot import. So:
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

/// The Locked-Out Moment (spec §5.16): a dismissable card, presented once
/// ``LockedOutAttemptTracker`` (or an equivalent future signal) fires, offering a "Share this"
/// export of the moment. This view never itself locks or shields anything — it's a promotional/
/// content moment layered on top of a shield that's already active, so CLAUDE.md's "any lock/shield
/// feature must always keep an emergency-unlock path" doesn't create a new obligation here (there's
/// no new lock state to escape); it's still always dismissable via `onDismiss`, as good practice for
/// any full-screen moment.
public struct LockedOutMomentView: View {
    private let content: LockedOutMomentContent
    private let onDismiss: () -> Void

    @State private var renderedImage: UIImage?

    /// - Parameters:
    ///   - content: Fully-composed display data — see ``LockedOutMomentContent``.
    ///   - onDismiss: Called when the user closes this moment without sharing (or after sharing).
    public init(content: LockedOutMomentContent, onDismiss: @escaping () -> Void) {
        self.content = content
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            header

            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    ShareCard(content: shareCardContent)
                        .frame(maxWidth: 320)

                    Text(Copy.lockedOut.acknowledgementLine)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
            }

            actions
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task {
            guard renderedImage == nil else { return }
            // `await`, not a direct call: `ShareCard.renderImage` is `@MainActor`-isolated, and
            // this task's environment has no Mac/Swift compiler to confirm whether SwiftUI's
            // `.task` closure is itself MainActor-isolated on the SDK this project targets. `await`
            // here is correct either way — a redundant `await` on an already-isolated call compiles
            // fine, while omitting a *required* one is a hard error — see this task's `knownIssues`.
            renderedImage = await ShareCard.renderImage(content: shareCardContent)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Copy.lockedOut.screenTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.lockedOut.dismissButtonTitle)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Actions (share / dismiss)

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let renderedImage {
                ShareLink(
                    item: Image(uiImage: renderedImage),
                    preview: SharePreview(
                        Copy.lockedOut.headline(appName: content.appName, blockingGoalSummary: content.blockingGoalSummary),
                        image: Image(uiImage: renderedImage)
                    )
                ) {
                    shareLabel
                }
                .buttonStyle(.plain)
            } else {
                preparingShareLabel
            }

            Button(Copy.lockedOut.dismissButtonTitle, action: onDismiss)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .buttonStyle(.plain)
        }
    }

    /// Styled to match `PrimaryButton`'s `.standard` visual treatment
    /// (`Core/Sources/Core/UI/Components/PrimaryButton.swift`). Not built by wrapping
    /// `PrimaryButton` itself: that component owns its own `Button`/action, and `ShareLink` needs
    /// to own the tap gesture here instead, so this mirrors its look with the same `Theme` tokens
    /// rather than nesting one tappable control inside another.
    private var shareLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
            Text(Copy.share.shareButtonTitle)
                .font(Theme.Typography.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .foregroundStyle(Theme.Colors.background)
        .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    /// `SwiftUI.ProgressView` is spelled out fully here — this file's module (the `ZANO` app
    /// target) also declares `App/ZANO/Features/Progress/ProgressView.swift`'s `struct
    /// ProgressView: View` (the Progress *screen*) at module scope; an unqualified `ProgressView()`
    /// in this same module would silently resolve to that screen instead of the system spinner
    /// (both are zero-argument-constructible `View`s, so this would compile with no error and just
    /// be wrong) — see that file's own header comment for the same gotcha called out from its side.
    private var preparingShareLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            SwiftUI.ProgressView()
                .tint(Theme.Colors.background)
            Text(Copy.share.preparingShareTitle)
                .font(Theme.Typography.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .foregroundStyle(Theme.Colors.background)
        .background(Theme.Colors.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    // MARK: - ShareCard content

    private var shareCardContent: ShareCardContent {
        ShareCardContent(
            title: Copy.lockedOut.headline(appName: content.appName, blockingGoalSummary: content.blockingGoalSummary),
            dayRings: [],
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
