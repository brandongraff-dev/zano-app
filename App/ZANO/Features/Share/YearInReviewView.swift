// YearInReviewView.swift
// App / ZANO / Features / Share
//
// "Your <year>": the year in review milestone (`Milestone.yearInReview`, `MilestoneEngine`), shown
// from December 1 to January 7 for a year with at least 14 earned days. Up to four swipeable 9:16
// pages, each a `MilestoneCardView` poster (the user's own buddy is on every one), and a Share action
// that posts the page on screen (rendered at 1080 x 1920 like every other poster):
//
//   1. Days earned in the year (always).
//   2. Hours locked in (only with at least one whole hour; never a zero hero).
//   3. Best month and how many days it had (only when there was one).
//   4. Best streak, with the year's top goal (or its earned-unlock count when no goal is named).
//
// Built like `MonthlyStoryView`, on purpose: three similar call sites beat a premature protocol.
// Copy: `Copy.milestone.*`, `Copy.share.*`. No user-facing string is composed here.

import SwiftUI
import Core

struct YearInReviewView: View {
    let review: YearInReview
    let onDismiss: () -> Void

    @State private var page = 0
    @State private var renderedImages: [Int: UIImage] = [:]
    @State private var shareRenderFailed = false
    @State private var renderAttempt = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(review: YearInReview, onDismiss: @escaping () -> Void) {
        self.review = review
        self.onDismiss = onDismiss
    }

    private var milestone: Milestone { .yearInReview(review) }
    private var voice: CoachVoice { CoachVoice.from(sharedDefaultsRaw: SharedDefaults.coachVoice) }

    /// The story's pages, in order.
    private var pages: [MilestoneCardContent] {
        var result = [
            MilestoneCardContent(
                eyebrow: Copy.milestone.yearEyebrow(year: review.year),
                numeral: "\(review.earnedDays)",
                unit: Copy.milestone.monthDaysUnit,
                line: Copy.milestone.yearIntroLine,
                hue: .volt
            ),
        ]
        if review.lockedHours > 0 {
            result.append(MilestoneCardContent(
                eyebrow: Copy.milestone.monthHoursEyebrow,
                numeral: "\(review.lockedHours)",
                unit: Copy.milestone.monthHoursUnit(hours: review.lockedHours),
                line: Copy.milestone.yearHoursLine,
                hue: .violet
            ))
        }
        if review.bestMonthDays > 0 {
            result.append(MilestoneCardContent(
                eyebrow: Copy.milestone.yearBestMonthEyebrow(monthName: review.bestMonthName()),
                numeral: "\(review.bestMonthDays)",
                unit: Copy.milestone.yearBestMonthUnit,
                line: Copy.milestone.yearBestMonthLine,
                hue: .sky
            ))
        }
        result.append(MilestoneCardContent(
            eyebrow: Copy.milestone.monthStreakEyebrow,
            numeral: "\(review.bestStreak)",
            unit: Copy.milestone.monthStreakUnit(days: review.bestStreak),
            line: review.topGoalTitle.map { Copy.milestone.yearTopGoalLine(goal: $0) }
                ?? Copy.milestone.yearUnlocksLine(count: review.earnedUnlocks),
            hue: .ember
        ))
        return result
    }

    var body: some View {
        let pages = self.pages
        VStack(spacing: 0) {
            ZanoGlassChip(Copy.milestone.yearlyMomentHeadline, systemImage: "gift.fill", tint: Theme.Colors.Ring.water)
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
    YearInReviewView(
        review: YearInReview(year: 2026, earnedDays: 212, earnedUnlocks: 260, lockedMinutes: 900 * 60,
                             bestStreak: 41, topGoalTitle: "Gym session", bestMonth: 3, bestMonthDays: 27),
        onDismiss: {}
    )
}
