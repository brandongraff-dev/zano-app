// WeeklyRecapShareView.swift
// App / ZANO / Features / Share
//
// docs/spec.md §5.14 "Weekly Report Card (shareable)": "Auto-generated Sunday night: rings for the
// week, best day, time reclaimed, streak, rank movement, and one LLM-written line of insight.
// Exportable as a 9:16 image. This is the organic-content engine." §9.6 "Weekly Recap Writer" is
// the backend job that produces the `Recap`/`RecapStats` this view renders; this file only turns
// an already-written `Recap` into the exportable image.
//
// STORY REDESIGN (2026-09-24). The recap is now a full-screen, swipeable story before it is a
// poster: intro (the living star + week dates) → time reclaimed → goals earned + streak → best day
// & toughest goal → the week's rings → the share card. Top progress segments, 4s auto-advance,
// tap left third = back / elsewhere = forward, swipe, hold to pause. Pages live in
// `RecapStoryPages.swift`; this file owns the pager, the timer and the share/export logic, which is
// unchanged. Auto-advance is off under VoiceOver (the story is one adjustable element instead) and
// for CI screenshot launches (`ScreenshotMode.screen != nil`), so a screenshot always sees a
// complete first page. The init is unchanged; no caller edits needed.
//   - "Toughest day": `RecapStats` has only `bestDay`, no per-weekday data, so page 4 pairs the best
//     day with the *goal* that pushed back hardest (lowest unclosed ring) rather than inventing a
//     worst day. Pages with nothing honest to show are skipped.
//
// Renders through `RecapPoster` (`SharePoster.swift`, this folder): a fixed 360 x 640pt canvas
// exported at scale 3 (= 1080 x 1920 px), with the on-screen preview being the same view scaled to
// fit, so what the user approves is what they post. It replaces the old `ShareCard` path, whose
// export laid a UI-sized type ramp out on a 1080pt canvas (text ~2% of image width) and whose fixed
// 44pt ring strip overflowed at five goals (see `SharePoster.swift`'s header for the full list).
// Mapped to the P7 mockup in docs/spec.md §16 ("9:16 shareable card: 'Week 6 · Rank Gold', 7 columns
// of daily rings, stats '4 workouts · 1,020g protein · 6h 40m time reclaimed', one line 'Best day:
// Thursday', small logo bottom right"), reconciled against what `Recap`/`RecapStats`
// (`Core/Sources/Core/Models/Recap.swift`, Session 1's frozen model) actually stores — see below for
// every place this mapping had to make a call instead of inventing a field that doesn't exist.
//
// Unlike `RecapCard` (`Core/Sources/Core/UI/Components/RecapCard.swift`), which deliberately takes
// plain caller-composed data instead of the `Recap` `@Model` class, this view takes `Recap` itself
// — that's this task's explicit brief ("renders a Recap model"). Reading a SwiftData model's stored
// properties directly inside a SwiftUI view body is the same pattern every other screen in
// `App/ZANO/Features` already uses for its `@Query` results; this file just receives its one `Recap`
// as an `init` parameter instead of querying for it itself, so it stays presentable from anywhere a
// caller already has one (`ProgressView`'s "Share this" action, a Sunday-recap push's deep link, a
// preview).
//
// Reconciling P7 vs. the frozen model (flagged, not guessed):
//   - "7 columns of DAILY rings": `RecapStats.goalCompletionRings` is documented as "per-goal
//     completion fraction for the week, keyed by the goal's id" — there is no per-weekday array
//     anywhere in `Recap`/`RecapStats`. `RecapCard.swift` reconciled the same tension the same way:
//     one ring per *goal*, not one per weekday. This view follows it — one `PosterRingData` per goal
//     (labeled with the goal's first word, truncated to fit the column) rather than inventing seven
//     fake day buckets from data that doesn't exist. The poster sizes its rings from the canvas
//     width, so any goal count fits.
//   - "Rank Gold": `RecapStats.rankMovement` is a *delta* ("positive = moved up"), not a rank-tier
//     name — no rank/season tier field exists yet anywhere in the frozen model (Seasons/Ranks are
//     spec §5.9, a v3 feature). Rather than fabricate a tier string, `rankTierLabel` below is an
//     optional caller-supplied parameter (`nil` today) so this view is ready for the future Seasons
//     session to pass one through with zero changes here.
//   - "Week 6": `Recap` has no "week N of the program" counter. `weekNumber` uses
//     `Calendar.current.component(.weekOfYear, from: recap.weekStart)` as the closest honest
//     stand-in — an assumption, not spec-exact.
//   - "4 workouts · 1,020g protein": `RecapStats` only has generic `goalsCompleted`/`goalsPlanned`
//     counts, not domain-specific per-goal-type totals. The hero is the time reclaimed (spec §5.15's
//     Time Reclaimed counter: the number people screenshot, `docs/design/competitive-research.md`
//     3.8), with goals completed as the stat line beneath. When nothing was reclaimed that week the
//     goals count becomes the hero instead, so a "0m" is never the biggest thing on the poster.
//   - The Weekly Recap Writer's LLM insight line (`Recap.text`, spec §9.6) is intentionally left off
//     the exported image: P7's own content list doesn't include it, and `RecapCard` already
//     surfaces it in-app.
//
// Copy: `Copy.share.*` (`ShareCopy.swift`) and `Copy.progress.*` (`ProgressCopy.swift`), reused
// rather than declaring near-duplicates for the same semantics. `Copy.share.weeklyRecapStatLine` is no
// longer used here: it folded the time reclaimed into the goals line, which would now say the hero's
// number twice.

import Foundation
import SwiftUI
import Core

/// Renders a `Recap` (docs/spec.md §5.14, §9.6; `Core/Sources/Core/Models/Recap.swift`) as a
/// swipeable story that ends on the exportable 9:16 poster. See this file's header for how each
/// mockup element maps onto the frozen `RecapStats` shape.
public struct WeeklyRecapShareView: View {
    private let recap: Recap
    /// Goal id → display title, resolved by the caller (this view has no `Goal` query of its own —
    /// same "caller resolves id → title" split `RecapCard.swift` documents for the same
    /// `RecapStats.goalCompletionRings` dictionary). A goal id with no entry here falls back to
    /// `Copy.progress.unknownGoalLabel`.
    ///
    /// No per-goal *color* parameter exists here (unlike `RingClusterItem.color` in the in-app
    /// `RecapCard`): the poster draws every ring in the single brand accent — correctly, per spec §15
    /// "ONE accent only" for a card meant to be recognizable as ZANO's on Instagram/TikTok.
    private let goalTitles: [UUID: String]
    /// Optional rank-tier label (e.g. `"Gold"`) — see this file's header on why this isn't
    /// resolved from `Recap`/`RecapStats` today. `nil` renders the title as just `"Week N"`.
    private let rankTierLabel: String?
    private let onDismiss: () -> Void

    // MARK: Story state

    /// Seconds each page stays up before auto-advancing.
    private static let pageDuration: Double = 4
    private static let tick: Double = 0.05

    @State private var pageIndex = 0
    /// Fill of the current page's top segment, 0...1.
    @State private var segmentProgress: Double = 0
    /// True while a finger is down on the story: auto-advance pauses, like any stories UI.
    @State private var isHolding = false
    @State private var pressStart: Date?
    /// Direction of the last page change, for the insertion edge.
    @State private var movingForward = true

    // MARK: Share state

    @State private var renderedImage: UIImage?
    /// `true` once the poster render has returned `nil` — see the `.task` below and
    /// `docs/design/ui-stress-test-findings.md` §3.6. Without a branch on this case, a render failure
    /// (low memory) would leave the action stuck on "Preparing…" forever, indistinguishable from
    /// "still working."
    @State private var shareRenderFailed = false
    /// Bumped by `retryShareRender()` to re-run the `.task(id:)` below on demand.
    @State private var renderAttempt = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

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
        let story = storyData
        let pages = storyPages(for: story)
        let index = min(pageIndex, pages.count - 1)
        let page = pages[index]

        ZStack {
            StoryBackdrop(glow: page.glow)
                .animation(reduceMotion ? .easeInOut(duration: 0.3) : .easeInOut(duration: 0.9), value: page)

            VStack(spacing: 0) {
                StoryProgressSegments(
                    count: pages.count,
                    index: index,
                    progress: autoAdvances && index < pages.count - 1 ? segmentProgress : 1
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)

                ShareMomentHeader(
                    title: nil,
                    dismissLabel: Copy.share.dismissButtonTitle,
                    onDismiss: onDismiss
                )

                GeometryReader { proxy in
                    ZStack {
                        pageView(page, story: story)
                            .id(page)
                            .transition(pageTransition)
                            .frame(width: proxy.size.width, height: proxy.size.height)

                        tapLayer(width: proxy.size.width, pageCount: pages.count)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Copy.share.storyPageAccessibilityValue(page: index + 1, total: pages.count))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: go(to: index + 1, pageCount: pages.count)
                    case .decrement: go(to: index - 1, pageCount: pages.count)
                    @unknown default: break
                    }
                }

                if page == .share {
                    actions
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.sm)
                        .transition(.opacity)
                }
            }
        }
        // Auto-advance: one timer per page, restarted whenever the page changes.
        .task(id: index) {
            await runPageTimer(pageCount: pages.count)
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
        // `Theme.swift`'s own header: fixed, dark-only design system — see
        // `docs/design/ui-stress-test-findings.md` §2.1 and `LockSetupView.swift`'s comment for
        // the full rationale.
        .preferredColorScheme(.dark)
    }

    // MARK: - Story

    /// Auto-advance is off for VoiceOver users (they page with swipe up/down on the adjustable
    /// element) and for CI screenshot launches, which must capture a complete first page.
    private var autoAdvances: Bool {
        !voiceOverEnabled && ScreenshotMode.screen == nil
    }

    /// Pages with nothing honest to show are skipped (no best day and no goal to compare; no rings).
    private func storyPages(for story: RecapStoryData) -> [RecapStoryPage] {
        var pages: [RecapStoryPage] = [.intro, .time, .goals]
        if story.bestDay != nil || story.toughest != nil { pages.append(.days) }
        if !story.rings.isEmpty { pages.append(.rings) }
        pages.append(.share)
        return pages
    }

    @ViewBuilder
    private func pageView(_ page: RecapStoryPage, story: RecapStoryData) -> some View {
        switch page {
        case .intro: RecapIntroPage(data: story)
        case .time: RecapTimePage(data: story)
        case .goals: RecapGoalsPage(data: story)
        case .days: RecapDaysPage(data: story)
        case .rings: RecapRingsPage(data: story)
        case .share: RecapSharePage(poster: poster)
        }
    }

    /// Tap the left third to go back, anywhere else to go forward; swipe left/right; hold to pause.
    /// One zero-distance drag handles all three so they never fight each other. Sits above the
    /// page, which has no controls of its own (the share button lives below this area).
    private func tapLayer(width: CGFloat, pageCount: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding else { return }
                        isHolding = true
                        pressStart = .now
                    }
                    .onEnded { value in
                        let held = pressStart.map { Date.now.timeIntervalSince($0) } ?? 0
                        isHolding = false
                        pressStart = nil
                        let dx = value.translation.width
                        let dy = value.translation.height
                        let current = min(pageIndex, pageCount - 1)
                        if abs(dx) > 40, abs(dx) > abs(dy) {
                            go(to: dx < 0 ? current + 1 : current - 1, pageCount: pageCount)
                        } else if held < 0.3, abs(dx) < 12, abs(dy) < 12 {
                            let back = value.location.x < width / 3
                            go(to: back ? current - 1 : current + 1, pageCount: pageCount)
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    private func go(to newIndex: Int, pageCount: Int) {
        let current = min(pageIndex, pageCount - 1)
        guard newIndex != current, (0 ..< pageCount).contains(newIndex) else { return }
        movingForward = newIndex > current
        segmentProgress = 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.Motion.springStandard) {
            pageIndex = newIndex
        }
    }

    private func runPageTimer(pageCount: Int) async {
        segmentProgress = 0
        guard autoAdvances, pageIndex < pageCount - 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(Self.tick * 1000)))
            guard !Task.isCancelled else { return }
            if isHolding { continue }
            segmentProgress = min(1, segmentProgress + Self.tick / Self.pageDuration)
            if segmentProgress >= 1 {
                go(to: pageIndex + 1, pageCount: pageCount)
                return
            }
        }
    }

    /// Forward: the next page slides in from the right. Back: from the left. Reduce Motion: fade.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: movingForward ? 48 : -48).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var storyData: RecapStoryData {
        let calendar = Calendar.current
        let start = recap.weekStart
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let dateStyle = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let rings = recap.stats.goalCompletionRings
            .compactMap { key, progress -> RecapStoryData.Ring? in
                guard let goalID = UUID(uuidString: key) else { return nil }
                let title = goalTitles[goalID] ?? Copy.progress.unknownGoalLabel
                return RecapStoryData.Ring(id: goalID, title: title, progress: progress)
            }
            .sorted { $0.title < $1.title }
        return RecapStoryData(
            weekTitle: Copy.share.weeklyRecapTitle(weekNumber: weekNumber, rankTierLabel: rankTierLabel),
            dateRange: Copy.share.storyDateRange(start: start.formatted(dateStyle), end: end.formatted(dateStyle)),
            timeReclaimedMinutes: recap.stats.timeReclaimedMinutes,
            goalsCompleted: recap.stats.goalsCompleted,
            goalsPlanned: recap.stats.goalsPlanned,
            streak: recap.stats.streak,
            rankMovement: recap.stats.rankMovement,
            bestDay: recap.stats.bestDay,
            rings: rings,
            insight: recap.text
        )
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
        // finishes, instead of a hard cut — docs/design/animation-opportunities.md row 10's
        // "satisfying share-sheet transition." Keyed on a small `Equatable` state enum, not the
        // image itself: `UIImage` isn't `Equatable`, which `.animation(_:value:)` requires.
        Group {
            switch shareRenderState {
            case .ready:
                if let renderedImage {
                    ShareLink(
                        item: Image(uiImage: renderedImage),
                        preview: SharePreview(
                            Copy.share.weeklyRecapTitle(weekNumber: weekNumber, rankTierLabel: rankTierLabel),
                            image: Image(uiImage: renderedImage)
                        )
                    ) {
                        ShareActionLabel(state: .ready)
                    }
                    .buttonStyle(.pressable)
                    .transition(shareControlTransition)
                }
            case .failed:
                // Terminal failure state instead of an indefinite spinner — see
                // `docs/design/ui-stress-test-findings.md` §3.6.
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

    /// Reduce Motion: plain fade, no scale.
    private var shareControlTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
    }

    // MARK: - Poster

    private var poster: RecapPoster {
        let minutes = recap.stats.timeReclaimedMinutes
        let hasReclaimedTime = minutes > 0
        let goalsLabel = Copy.progress.goalsCompletedLabel(
            completed: recap.stats.goalsCompleted,
            planned: recap.stats.goalsPlanned
        )
        return RecapPoster(
            title: Copy.share.weeklyRecapTitle(weekNumber: weekNumber, rankTierLabel: rankTierLabel),
            heroValue: hasReclaimedTime ? formatDuration(minutes: minutes) : goalsLabel,
            heroCaption: hasReclaimedTime ? Copy.progress.timeReclaimedTitle : Copy.progress.recapSectionTitle,
            rings: goalRings,
            statLine: hasReclaimedTime ? goalsLabel : nil,
            highlightLine: recap.stats.bestDay.map { Copy.progress.bestDayLabel(day: $0) },
            footerLabel: Copy.share.footerWordmark
        )
    }

    /// One ring per goal from `recap.stats.goalCompletionRings` — see this file's header
    /// ("Reconciling P7 vs. the frozen model") for why this is per-goal, not per-weekday. Sorted by
    /// label for a stable, deterministic column order across renders.
    private var goalRings: [PosterRingData] {
        recap.stats.goalCompletionRings
            .compactMap { key, progress -> PosterRingData? in
                guard let goalID = UUID(uuidString: key) else { return nil }
                let title = goalTitles[goalID] ?? Copy.progress.unknownGoalLabel
                return PosterRingData(id: goalID, label: shortLabel(title), progress: progress)
            }
            .sorted { $0.label < $1.label }
    }

    /// The poster's ring column is narrow (up to five per row on a 312pt content width), so a full
    /// goal title is shortened here, before it reaches the poster, to a compact column label.
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

    /// Same "Xh Ym" / "Ym" formatting `ProgressView.swift` uses for `RecapStats.timeReclaimedMinutes`
    /// (spec §5.15) — duplicated rather than factored into a shared helper, since neither this file
    /// nor that one is free to add a new shared Core utility file for a four-line formatter
    /// (CLAUDE.md: "don't add abstractions... beyond what the current session's scope requires").
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
