// MilestonePresenter.swift
// App / ZANO / Features / Share
//
// Decides *when* a milestone moment shows. `MilestoneEngine` (Core) decides *what* has been reached;
// this type turns that into at most one full-screen moment per app session, at a calm moment:
//
//   - Never during onboarding (the modifier lives on the tab UI only, and an unlock that lands while
//     onboarding is still running suppresses milestones for the rest of that session, so the person
//     isn't hit with a second celebration right after onboarding's own first-win moment).
//   - Never on top of the unlock celebration or the ringing alarm. After an earned unlock the
//     moment is held until the celebration closes: the root celebration (`AppRouter.unlockCelebration`)
//     is observed here; Today's own celebration reports back through `celebrationDidFinish()`.
//   - Never during CI screenshot launches.
//   - A milestone is written to the engine's fire-once ledger the moment its cover appears, so a
//     crash or a swipe-away never shows it twice.
//
// Hooks (applied by the shell, not by this file):
//   - `.zanoMilestoneMoments()` on `MainTabView`.
//   - `MilestonePresenter.shared.checkForNewMilestones()` on every foreground.
//   - `MilestonePresenter.shared.handleUnlock(sessionID:)` whenever
//     `LockEngineManager.lastUnlockedSessionID` changes (after `router.handleUnlock`).
//   - `MilestonePresenter.shared.celebrationDidFinish()` when Today's own celebration closes.

import SwiftUI
import SwiftData
import os
import Core

@MainActor
@Observable
final class MilestonePresenter {
    static let shared = MilestonePresenter()

    /// The milestone waiting to be shown (or on screen), `nil` when there is none.
    private(set) var pending: Milestone?
    /// Held while an unlock celebration is (about to be) on screen.
    private(set) var isHeldForCelebration = false

    @ObservationIgnored private var hasPresentedThisSession = false
    @ObservationIgnored private var isSuppressedThisSession = false
    /// The id of the milestone whose cover actually appeared.
    @ObservationIgnored private var presentedID: String?
    @ObservationIgnored private let engine: MilestoneEngine
    @ObservationIgnored private let logger = Logger(subsystem: "com.zano.app", category: "MilestonePresenter")

    init(engine: MilestoneEngine = .shared) {
        self.engine = engine
    }

    // MARK: Hooks

    /// Evaluates local data and queues the highest-priority new milestone, if this session hasn't
    /// shown one yet. Cheap; call on every foreground.
    func checkForNewMilestones(now: Date = .now) {
        guard ScreenshotMode.screen == nil else { return }
        guard !hasPresentedThisSession, !isSuppressedThisSession, pending == nil else { return }
        guard AppRouter.shared.hasCompletedOnboarding else { return }
        pending = engine.evaluate(now: now).first
        if let pending {
            logger.info("Milestone queued: \(pending.id, privacy: .public)")
        }
    }

    /// After a lock ends. For an earned unlock, holds the moment until the celebration closes and
    /// then shows any milestone that unlock just reached. An unlock during onboarding (the first-win
    /// lock) suppresses milestones for the rest of this session.
    func handleUnlock(sessionID: UUID) {
        guard AppRouter.shared.hasCompletedOnboarding else {
            isSuppressedThisSession = true
            return
        }
        let context = ModelContext(ModelContainer.appGroup)
        var descriptor = FetchDescriptor<LockSession>(predicate: #Predicate<LockSession> { $0.id == sessionID })
        descriptor.fetchLimit = 1
        // Compared in Swift, never inside the predicate (enum comparisons in `#Predicate` crash).
        guard let session = (try? context.fetch(descriptor))?.first, session.unlockKind == .earned else { return }
        isHeldForCelebration = true
        checkForNewMilestones()
    }

    /// The unlock celebration closed: release the hold and show what's queued.
    func celebrationDidFinish() {
        guard isHeldForCelebration else { return }
        isHeldForCelebration = false
        checkForNewMilestones()
    }

    /// Never show milestones again this session (e.g. right after onboarding finishes).
    func suppressForThisSession() {
        isSuppressedThisSession = true
        if presentedID == nil { pending = nil }
    }

    // MARK: Presentation

    /// What the cover should show right now, or `nil` while anything outranks it.
    func presentableMilestone(router: AppRouter) -> Milestone? {
        guard let pending,
              router.hasCompletedOnboarding,
              router.unlockCelebration == nil,
              !router.isAlarmRingingPresented,
              !isHeldForCelebration else { return nil }
        return pending
    }

    /// The cover appeared: record it in the fire-once ledger.
    fileprivate func didPresent(_ milestone: Milestone) {
        guard presentedID != milestone.id else { return }
        presentedID = milestone.id
        hasPresentedThisSession = true
        engine.markCelebrated(milestone)
        Analytics.shared.capture(event: "milestone_presented", properties: ["milestone": milestone.id])
    }

    /// The person closed the moment.
    fileprivate func dismiss() {
        pending = nil
    }

    /// SwiftUI wrote `nil` back through the cover binding. Only clears a milestone that actually
    /// appeared; a `nil` written while the cover was merely held back keeps it queued.
    fileprivate func coverDidClose() {
        guard let pending, pending.id == presentedID else { return }
        self.pending = nil
    }

    /// The app went to the background: a celebration that never reported back can't hold forever.
    fileprivate func releaseHold() {
        isHeldForCelebration = false
    }
}

// MARK: - View modifier

extension View {
    /// Presents milestone moments (`MilestonePresenter`) over this view as a full-screen cover. Apply
    /// once, to the main tab UI.
    func zanoMilestoneMoments() -> some View {
        modifier(MilestoneMomentsModifier())
    }
}

private struct MilestoneMomentsModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let presenter = MilestonePresenter.shared
        let router = AppRouter.shared
        let item = presenter.presentableMilestone(router: router)
        let celebrationIsUp = router.unlockCelebration != nil

        content
            .fullScreenCover(
                item: Binding<Milestone?>(
                    get: { item },
                    set: { newValue in
                        if newValue == nil { presenter.coverDidClose() }
                    }
                )
            ) { milestone in
                Group {
                    switch milestone {
                    case .monthlyStory(let story):
                        MonthlyStoryView(story: story, onDismiss: { presenter.dismiss() })
                    default:
                        MilestoneMomentView(milestone: milestone, onDismiss: { presenter.dismiss() })
                    }
                }
                .preferredColorScheme(.dark)
                .onAppear { presenter.didPresent(milestone) }
            }
            // The root unlock celebration closing releases the hold.
            .onChange(of: celebrationIsUp) { wasUp, isUp in
                if wasUp, !isUp { presenter.celebrationDidFinish() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { presenter.releaseHold() }
            }
    }
}
