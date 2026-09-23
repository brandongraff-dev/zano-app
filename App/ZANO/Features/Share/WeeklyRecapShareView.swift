// WeeklyRecapShareView.swift
// App / ZANO / Features / Share
//
// docs/spec.md §5.14 "Weekly Report Card (shareable)": "Auto-generated Sunday night: rings for the
// week, best day, time reclaimed, streak, rank movement, and one LLM-written line of insight.
// Exportable as a 9:16 image. This is the organic-content engine." §9.6 "Weekly Recap Writer" is
// the backend job that produces the `Recap`/`RecapStats` this view renders; this file only turns
// an already-written `Recap` into the exportable image.
//
// Renders through `ShareCard` (`Core/Sources/Core/UI/Components/ShareCard.swift`, docs/spec.md
// §15's core component list — "ShareCard (9:16 renderer)"), called exactly per its real, already-
// built public shape (`ShareCard(content:)`, `ShareCardContent`, `ShareCardDayRing`,
// `ShareCard.renderImage(content:size:scale:)`) — read in full before writing this file, not
// guessed. Mapped to the P7 mockup in docs/spec.md §16 ("9:16 shareable card: 'Week 6 · Rank Gold',
// 7 columns of daily rings, stats '4 workouts · 1,020g protein · 6h 40m time reclaimed', one line
// 'Best day: Thursday', small logo bottom right"), reconciled against what `Recap`/`RecapStats`
// (`Core/Sources/Core/Models/Recap.swift`, Session 1's frozen model, read in full before writing
// this file) actually stores — see "Reconciling P7 vs. the frozen model" below for every place this
// mapping had to make a call instead of inventing a field that doesn't exist.
//
// Unlike `RecapCard` (`Core/Sources/Core/UI/Components/RecapCard.swift`), which deliberately takes
// plain caller-composed data instead of the `Recap` `@Model` class, this view takes `Recap` itself
// — that's this task's explicit brief ("renders a Recap model via ShareCard"). Reading a SwiftData
// model's stored properties directly inside a SwiftUI view body is the same pattern every other
// screen in `App/ZANO/Features` already uses for its `@Query` results (see `TodayView.swift`,
// `ProgressView.swift`); this file just receives its one `Recap` as an `init` parameter instead of
// querying for it itself, so it stays presentable from anywhere a caller already has one (a
// `ProgressView` "Share" button, a Sunday-recap push's deep link, a preview).
//
// Reconciling P7 vs. the frozen model (flagged, not guessed):
//   - "7 columns of DAILY rings": `RecapStats.goalCompletionRings` is documented as "per-goal
//     completion fraction for the week, keyed by the goal's id" — there is no per-weekday array
//     anywhere in `Recap`/`RecapStats`. `RecapCard.swift` (already built) reconciled the exact same
//     tension the same way: it renders `goalCompletionRings` through `RingCluster` as one ring per
//     *goal*, not one per weekday. This view follows that same, already-established reconciliation
//     — one `ShareCardDayRing` per goal (labeled with the goal's title, truncated to fit the
//     column) rather than inventing seven fake day buckets from data that doesn't exist. `ShareCard`
//     itself documents its `dayRings` as "typically 7 entries... but this view lays out however
//     many are supplied," so it was already designed to accept this.
//   - "Rank Gold": `RecapStats.rankMovement` is a *delta* ("positive = moved up"), not a rank-tier
//     name — no rank/season tier field exists yet anywhere in the frozen model (Seasons/Ranks are
//     spec §5.9, a v3 feature, §17 session 13). Rather than fabricate a tier string, `rankTierLabel`
//     below is an optional caller-supplied parameter (`nil` today) so this view is ready for the
//     future Seasons session to pass one through with zero changes here.
//   - "Week 6": `Recap` has no "week N of the program" counter. `weekNumber` below uses
//     `Calendar.current.component(.weekOfYear, from: recap.weekStart)` (ISO-style week-of-year) as
//     the closest honest stand-in — flagged as an assumption, not spec-exact, in this task's
//     `decisions`.
//   - "4 workouts · 1,020g protein": `RecapStats` only has generic `goalsCompleted`/`goalsPlanned`
//     counts, not domain-specific per-goal-type totals (workout count, protein grams) broken out
//     separately. The stat line below is composed from what's actually stored:
//     goalsCompleted/goalsPlanned + `timeReclaimedMinutes` — still "stats" in the spirit of the
//     mockup, just not the exact literal numbers it shows (those are illustrative example content,
//     not a literal schema).
//   - The Weekly Recap Writer's LLM insight line (`Recap.text`, spec §9.6) is intentionally left
//     off the exported image: P7's own content list (rings, stat line, "Best day: X", logo) doesn't
//     include it, and `RecapCard` already surfaces it in-app. Adding it to the export would be a
//     presentational choice beyond this task's literal P7 mapping.
//
// Same "ASSUMED API" convention `LockedOutMomentView.swift` (this folder) and `ProgressView.swift`/
// `LockSetupView.swift` already established — see this file's own list below.
//
// ASSUMED API — `Copy.share.*` / `Copy.progress.*` (`Core/Sources/Core/Copy`, not owned by this
// task). Reuses `Copy.progress.bestDayLabel(day:)` / `Copy.progress.unknownGoalLabel` rather than
// declaring near-duplicate `Copy.share.*` members for the exact same semantics `ProgressView.swift`
// already assumes — one shared meaning, one assumed signature:
//
//   Copy.share.weeklyRecapScreenTitle: String                                  // "Your Week"
//   Copy.share.weeklyRecapTitle(weekNumber: Int, rankTierLabel: String?) -> String
//       // e.g. "Week 6" or "Week 6 · Rank Gold" when `rankTierLabel` is supplied.
//   Copy.share.weeklyRecapStatLine(goalsCompleted: Int, goalsPlanned: Int, timeReclaimedLabel: String) -> String
//       // e.g. "5 of 7 goals · 6h 40m reclaimed"
//   Copy.share.shareButtonTitle: String                                        // already assumed
//       // by `LockedOutMomentView.swift` — spec §5.16's literal "Share this".
//   Copy.share.preparingShareTitle: String                                     // already assumed
//       // by `LockedOutMomentView.swift`.
//   Copy.share.shareFailedRetryLabel: String                                   // new, added by
//       // the accessibility/stress-test pass (docs/design/ui-stress-test-findings.md §3.6);
//       // already assumed by `LockedOutMomentView.swift` (this folder) — same key, same nil-
//       // render-failure gap in both files.
//   Copy.share.dismissButtonTitle: String                                      // "Close"
//   Copy.share.footerWordmark: String                                         // already assumed
//       // by `LockedOutMomentView.swift` — same small bottom-right logo text on every export.
//   Copy.progress.bestDayLabel(day: String) -> String                          // already assumed
//       // by `ProgressView.swift` — "Best day: Thursday".
//   Copy.progress.unknownGoalLabel: String                                     // already assumed
//       // by `ProgressView.swift` — fallback when a recap's goal id no longer resolves to a Goal.

import Foundation
import SwiftUI
import Core

/// Renders a `Recap` (docs/spec.md §5.14, §9.6; `Core/Sources/Core/Models/Recap.swift`) as an
/// exportable 9:16 `ShareCard`, per the P7 mockup (§16). See this file's header for exactly how
/// each mockup element maps onto the frozen `RecapStats` shape.
public struct WeeklyRecapShareView: View {
    private let recap: Recap
    /// Goal id → display title, resolved by the caller (this view has no `Goal` query of its own —
    /// same "caller resolves id → title" split `RecapCard.swift` already documents for the exact
    /// same `RecapStats.goalCompletionRings` dictionary). A goal id with no entry here falls back to
    /// `Copy.progress.unknownGoalLabel`.
    ///
    /// No per-goal *color* parameter exists here (unlike `RingClusterItem.color` in the in-app
    /// `RecapCard`): `ShareCard`'s own `dayRingsStrip` hardcodes every ring to the single brand
    /// accent (`Theme.Colors.accent`) — correctly, per spec §15 "ONE accent only" for a card meant
    /// to be recognizable as ZANO's on Instagram/TikTok — so there is no per-ring color for a caller
    /// to supply in the first place.
    private let goalTitles: [UUID: String]
    /// Optional rank-tier label (e.g. `"Rank Gold"`) — see this file's header on why this isn't
    /// resolved from `Recap`/`RecapStats` today. `nil` renders the title as just `"Week N"`.
    private let rankTierLabel: String?
    private let onDismiss: () -> Void

    @State private var renderedImage: UIImage?
    /// `true` once `ShareCard.renderImage` has returned `nil` — see the `.task` below and
    /// `docs/design/ui-stress-test-findings.md` §3.6 (identical gap `LockedOutMomentView.swift`,
    /// this folder, had). Previously nothing branched on this case, so a render failure left this
    /// screen stuck on `preparingShareLabel` forever, indistinguishable from "still working."
    @State private var shareRenderFailed = false
    /// Bumped by `retryShareRender()` to re-run the `.task(id:)` below on demand.
    @State private var renderAttempt = 0
    /// Drives the card's one-shot entrance reveal below — see `body`'s `.onAppear`. Deliberately
    /// **not** anything `ShareCard.swift` itself knows about (this view only ever applies
    /// `.scaleEffect`/`.opacity` to the `ShareCard(content:)` instance it composes here) — that
    /// file is also constructed a second, separate time by `ShareCard.renderImage` purely for
    /// off-screen `ImageRenderer` capture, per `docs/design/animation-opportunities.md` row 10's
    /// explicit constraint: an animation baked into `ShareCard`'s own `body` would risk being
    /// mid-flight when that separate instance is rasterized. Animating at this call site instead
    /// leaves that off-screen instance untouched.
    @State private var cardAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - recap: The week's `Recap`, typically the same instance a `@Query(sort: \Recap.weekStart,
    ///     order: .reverse)` result already produced elsewhere (e.g. `ProgressView`'s recap
    ///     section).
    ///   - goalTitles: Goal id → title lookup for labeling each ring. Defaults to empty, in which
    ///     case every ring falls back to `Copy.progress.unknownGoalLabel`.
    ///   - rankTierLabel: Optional caller-supplied rank-tier string (spec §5.9, not in the frozen
    ///     model yet). Defaults to `nil`.
    ///   - onDismiss: Called when the user closes this view.
    public init(
        recap: Recap,
        goalTitles: [UUID: String] = [:],
        rankTierLabel: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.recap = recap
        self.goalTitles = goalTitles
        self.rankTierLabel = rankTierLabel
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            header

            ScrollView {
                ShareCard(content: shareCardContent)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                    .scaleEffect(reduceMotion || cardAppeared ? 1 : 0.92)
                    .opacity(cardAppeared ? 1 : 0)
            }

            actions
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task(id: renderAttempt) {
            guard renderedImage == nil else { return }
            shareRenderFailed = false
            // See `LockedOutMomentView.swift` (this folder) for why this is `await`ed even though
            // `ShareCard.renderImage` isn't `async` — it's `@MainActor`-isolated, and `await` here
            // is correct whether or not `.task`'s closure is itself MainActor-isolated on the SDK
            // this project targets (unverifiable without a Mac/Swift compiler in this environment).
            if let image = await ShareCard.renderImage(content: shareCardContent) {
                renderedImage = image
            } else {
                shareRenderFailed = true
            }
        }
        // The card's one-shot arrival, per docs/design/animation-opportunities.md row 10: scale
        // 0.92→1.0 + fade in, `springStandard`-family spring, fired once on appear. Reduce Motion:
        // opacity-only, no scale — same Part 0 pattern as everywhere else in this wave.
        .onAppear {
            guard !cardAppeared else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.8)) {
                cardAppeared = true
            }
        }
        // `Theme.swift`'s own header: fixed, dark-only design system — see
        // `docs/design/ui-stress-test-findings.md` §2.1 and `LockSetupView.swift`'s comment for
        // the full rationale.
        .preferredColorScheme(.dark)
    }

    private func retryShareRender() {
        renderedImage = nil
        shareRenderFailed = false
        renderAttempt += 1
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(Copy.share.weeklyRecapScreenTitle)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Colors.text)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.share.dismissButtonTitle)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.md)
    }

    // MARK: - Actions (share / dismiss)

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Group {
                if let renderedImage {
                    ShareLink(
                        item: Image(uiImage: renderedImage),
                        preview: SharePreview(
                            Copy.share.weeklyRecapTitle(weekNumber: weekNumber, rankTierLabel: rankTierLabel),
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        shareLabel
                    }
                    .buttonStyle(.plain)
                    .transition(shareControlTransition)
                } else if shareRenderFailed {
                    // Terminal failure state instead of an indefinite spinner — see
                    // `docs/design/ui-stress-test-findings.md` §3.6.
                    Button(action: retryShareRender) {
                        shareFailedLabel
                    }
                    .buttonStyle(.plain)
                    .transition(shareControlTransition)
                } else {
                    preparingShareLabel
                        .transition(shareControlTransition)
                }
            }
            // The "Preparing…" spinner crossfades into the real Share control the moment
            // `ShareCard.renderImage` finishes, instead of a hard cut — docs/design/
            // animation-opportunities.md row 10's "satisfying share-sheet transition." Keyed on a
            // small `Equatable` state enum, not the image itself: `UIImage` isn't `Equatable`,
            // which `.animation(_:value:)` requires.
            .animation(
                reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard,
                value: shareRenderState
            )

            Button(Copy.share.dismissButtonTitle, action: onDismiss)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.muted)
                .buttonStyle(.plain)
        }
    }

    /// The three states `actions` renders — see the `.animation(value:)` above.
    private enum ShareRenderState: Equatable {
        case preparing
        case ready
        case failed
    }

    private var shareRenderState: ShareRenderState {
        if renderedImage != nil { return .ready }
        if shareRenderFailed { return .failed }
        return .preparing
    }

    /// Reduce Motion: plain fade, no scale — same Part 0 pattern as the card reveal above.
    private var shareControlTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
    }

    /// Same visual treatment as `LockedOutMomentView.shareLabel` (this folder) — see that file's
    /// doc comment for why this isn't built by wrapping `PrimaryButton` itself. Kept as an
    /// independent, file-private copy rather than a shared internal helper: both files are owned by
    /// this same task, but each stays self-contained on its own so neither depends on the other's
    /// compile order or risks an accidental signature drift breaking both at once for a ~10-line
    /// view.
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

    /// `SwiftUI.ProgressView` spelled out fully — see `LockedOutMomentView.preparingShareLabel`'s
    /// doc comment (this folder) for why an unqualified `ProgressView()` would silently resolve to
    /// this same app module's `ProgressView` *screen* (`App/ZANO/Features/Progress/
    /// ProgressView.swift`) instead of the system spinner.
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

    /// The terminal render-failure state — same visual treatment as
    /// `LockedOutMomentView.shareFailedLabel` (this folder). Wrapped in a `Button` by its caller
    /// in `actions`.
    private var shareFailedLabel: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .semibold))
            Text(Copy.share.shareFailedRetryLabel)
                .font(Theme.Typography.headline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .foregroundStyle(Theme.Colors.text)
        .background(Theme.Colors.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .strokeBorder(Theme.Colors.danger.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - ShareCard content

    private var shareCardContent: ShareCardContent {
        ShareCardContent(
            title: Copy.share.weeklyRecapTitle(weekNumber: weekNumber, rankTierLabel: rankTierLabel),
            dayRings: goalRings,
            statLine: Copy.share.weeklyRecapStatLine(
                goalsCompleted: recap.stats.goalsCompleted,
                goalsPlanned: recap.stats.goalsPlanned,
                timeReclaimedLabel: formatDuration(minutes: recap.stats.timeReclaimedMinutes)
            ),
            highlightLine: recap.stats.bestDay.map { Copy.progress.bestDayLabel(day: $0) },
            footerLabel: Copy.share.footerWordmark
        )
    }

    /// One ring per goal from `recap.stats.goalCompletionRings` — see this file's header
    /// ("Reconciling P7 vs. the frozen model") for why this is per-goal, not per-weekday. Sorted by
    /// label for a stable, deterministic column order across renders.
    private var goalRings: [ShareCardDayRing] {
        recap.stats.goalCompletionRings
            .compactMap { key, progress -> ShareCardDayRing? in
                guard let goalID = UUID(uuidString: key) else { return nil }
                let title = goalTitles[goalID] ?? Copy.progress.unknownGoalLabel
                return ShareCardDayRing(id: goalID, label: shortLabel(title), progress: progress)
            }
            .sorted { $0.label < $1.label }
    }

    /// `ShareCard`'s ring column is narrow (modeled on the P7 mockup's 3-letter weekday labels,
    /// e.g. "Mon") and its `Text(day.label)` has no truncation mode of its own to rely on (this
    /// view can't edit `ShareCard.swift` to add one) — so a full goal title is shortened here,
    /// before it ever reaches `ShareCard`, to the same spirit of a compact column label.
    private func shortLabel(_ title: String) -> String {
        let firstWord = title.split(separator: " ").first.map(String.init) ?? title
        guard firstWord.count > 6 else { return firstWord }
        return String(firstWord.prefix(5)) + "…"
    }

    // MARK: - Formatting

    /// ISO-style week-of-year, standing in for spec §16's "Week 6" — see this file's header
    /// ("Reconciling P7 vs. the frozen model") for why this is an assumption, not a stored field.
    private var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: recap.weekStart)
    }

    /// Same "Xh Ym" / "Ym" formatting `ProgressView.swift` already uses for
    /// `RecapStats.timeReclaimedMinutes` (spec §5.15) — duplicated rather than factored into a
    /// shared helper, since neither this file nor that one is free to add a new shared Core utility
    /// file for a four-line formatter (CLAUDE.md: "don't add abstractions... beyond what the
    /// current session's scope requires").
    private func formatDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        guard hours > 0 else { return "\(mins)m" }
        return "\(hours)h \(mins)m"
    }
}

#Preview {
    let goalA = UUID()
    let goalB = UUID()
    let goalC = UUID()
    let recap = Recap(
        userID: UUID(),
        weekStart: Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now,
        text: "Solid week — Thursday was your best day. Try locking in Saturday's focus block next.",
        stats: RecapStats(
            goalCompletionRings: [
                goalA.uuidString: 0.86,
                goalB.uuidString: 1.0,
                goalC.uuidString: 0.64
            ],
            bestDay: "Thursday",
            timeReclaimedMinutes: 400,
            streak: 14,
            rankMovement: 2,
            goalsCompleted: 12,
            goalsPlanned: 14
        )
    )

    return WeeklyRecapShareView(
        recap: recap,
        goalTitles: [
            goalA: "Workout",
            goalB: "Focus",
            goalC: "Protein"
        ],
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
