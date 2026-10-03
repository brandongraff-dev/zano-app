// MonthlyStoryView.swift
// App / ZANO / Features / Share
//
// "Your <Month>": the monthly story milestone (`Milestone.monthlyStory`, `MilestoneEngine`). Two or
// three swipeable 9:16 pages, each a `MilestoneCardView` poster, and a Share action that posts the
// page on screen (rendered at 1080 x 1920 like every other poster):
//
//   1. Days earned (always; the story only exists for a month with at least 3 earned days).
//   2. Hours locked in (only when the month had at least one whole hour; never a zero hero).
//   3. Best streak, with the month's top goal (or its earned-unlock count when no goal is named).
//
// All pages are rendered once up front, so swiping never waits on a render. Copy:
// `Copy.milestone.*`, `Copy.share.*`. No user-facing string is composed here.

import SwiftUI
import Core

struct MonthlyStoryView: View {
    let story: MonthlyStory
    let onDismiss: () -> Void

    @State private var page = 0
    @State private var renderedImages: [Int: UIImage] = [:]
    @State private var shareRenderFailed = false
    @State private var renderAttempt = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(story: MonthlyStory, onDismiss: @escaping () -> Void) {
        self.story = story
        self.onDismiss = onDismiss
    }

    private var milestone: Milestone { .monthlyStory(story) }
    private var voice: CoachVoice { CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice) }

    /// The story's pages, in order.
    private var pages: [MilestoneCardContent] {
        let monthName = story.monthName()
        var result = [
            MilestoneCardContent(
                eyebrow: Copy.milestone.monthEyebrow(monthName: monthName),
                numeral: "\(story.earnedDays)",
                unit: Copy.milestone.monthDaysUnit,
                line: Copy.milestone.monthIntroLine,
                hue: .sky
            ),
        ]
        if story.lockedHours > 0 {
            result.append(MilestoneCardContent(
                eyebrow: Copy.milestone.monthHoursEyebrow,
                numeral: "\(story.lockedHours)",
                unit: Copy.milestone.monthHoursUnit(hours: story.lockedHours),
                line: Copy.milestone.monthHoursLine,
                hue: .violet
            ))
        }
        result.append(MilestoneCardContent(
            eyebrow: Copy.milestone.monthStreakEyebrow,
            numeral: "\(story.bestStreak)",
            unit: Copy.milestone.monthStreakUnit(days: story.bestStreak),
            line: story.topGoalTitle.map { Copy.milestone.monthTopGoalLine(goal: $0) }
                ?? Copy.milestone.monthUnlocksLine(count: story.earnedUnlocks),
            hue: .ember
        ))
        return result
    }

    var body: some View {
        let pages = self.pages
        VStack(spacing: 0) {
            ZanoGlassChip(Copy.milestone.monthlyMomentHeadline, systemImage: "calendar", tint: Theme.Colors.Ring.water)
                .padding(.top, Theme.Spacing.md)
                .accessibilityAddTraits(.isHeader)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    SharePosterPreview(poster: MilestoneCardView(content: pages[index]))
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .accessibilityHint(Copy.milestone.monthlySwipeHint)
            .accessibilityValue(Copy.share.storyPageAccessibilityValue(page: page + 1, total: pages.count))
            .scaleEffect(reduceMotion || appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zanoBackdrop()
        .zanoActionBar {
            VStack(spacing: Theme.Spacing.sm) {
                Text(Copy.milestone.coachLine(for: milestone, voice: voice))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                shareAction
                Button(action: onDismiss) {
                    Text(Copy.milestone.notNowLabel)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.muted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .task(id: renderAttempt) {
            shareRenderFailed = false
            for (index, content) in pages.enumerated() where renderedImages[index] == nil {
                if let image = await SharePosterRenderer.image(of: MilestoneCardView(content: content)) {
                    renderedImages[index] = image
                } else {
                    shareRenderFailed = true
                }
            }
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.8)) {
                appeared = true
            }
        }
        .sensoryFeedback(.selection, trigger: page)
        .preferredColorScheme(.dark)
    }

    // MARK: - Share (the page on screen)

    @ViewBuilder
    private var shareAction: some View {
        Group {
            if let image = renderedImages[page] {
                ShareLink(
                    item: Image(uiImage: image),
                    message: Text(Copy.milestone.shareMessage(for: milestone)),
                    preview: SharePreview(
                        Copy.milestone.eyebrow(for: milestone),
                        image: Image(uiImage: image)
                    )
                ) {
                    ShareActionLabel(state: .ready)
                }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded {
                    Analytics.shared.capture(event: "milestone_share_tapped", properties: ["milestone": milestone.id, "page": page])
                })
            } else if shareRenderFailed {
                Button {
                    shareRenderFailed = false
                    renderAttempt += 1
                } label: {
                    ShareActionLabel(state: .failed)
                }
                .buttonStyle(.pressable)
            } else {
                ShareActionLabel(state: .preparing)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.Motion.springStandard, value: renderedImages[page] != nil)
    }
}

#Preview {
    MonthlyStoryView(
        story: MonthlyStory(year: 2026, month: 9, earnedDays: 21, earnedUnlocks: 26,
                            lockedMinutes: 84 * 60, bestStreak: 12, topGoalTitle: "Gym session"),
        onDismiss: {}
    )
}
