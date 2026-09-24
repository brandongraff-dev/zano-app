// OnboardingFlowState.swift
// App / Features / Onboarding
//
// Owned by: this session (Onboarding screens 1-8 + this file). Sole owner of this file — sibling
// session "onboarding-2" (screens 9-14: Wake-up moment, Plan reveal, Commitment, Permission
// priming, Paywall, First win) calls this type's public/internal API from its own screen files,
// but never edits this file (CLAUDE.md "stay strictly inside your assigned file list").
//
// docs/spec.md §7 "Onboarding Flow (screen by screen)": 14 screens total, numbered 1-14 below
// exactly as spec numbers them, so `currentScreen` doubles as a direct cross-reference into that
// section for whoever reads either side of this flow.
//
//   1  Hook                                  <- Screen1Hook.swift            (this session)
//   2  Social proof strip                    <- Screen2SocialProof.swift     (this session)
//   3  Q1 Main goal                          <- Screen3MainGoal.swift        (this session)
//   4  Q2 Which apps steal your time         <- Screen4AppSelection.swift    (this session)
//   5  Q3 Daily phone time                   <- Screen5PhoneTime.swift       (this session)
//   6  Q4 Current vs target workouts/week    <- Screen6Workouts.swift        (this session)
//   7  Q5 When do you usually fall off       <- Screen7FallOff.swift         (this session)
//   8  Q6 Coach voice                        <- Screen8CoachVoice.swift      (this session)
//   9  Wake-up moment                        <- onboarding-2
//   10 Plan reveal                           <- onboarding-2
//   11 Commitment (hold to commit)           <- onboarding-2
//   12 Paywall (hard; PaywallView.swift)     <- onboarding-2
//   13 Permission priming (notifications;    <- onboarding-2
//      Screen12PermissionPriming.swift keeps its old name)
//   (Order per decision 2026-09-23: nothing sits between Commitment and the paywall. Wired in
//   `OnboardingContainerView.screen(for:)`; numbers are the CI `-ZANOScreen onboarding-N` ids.)
//   14 First win                             <- onboarding-2
//
// Scope note: only `currentScreen`, the six Q1-Q6 answer properties, and `committedAt` (screen 11
// explicitly "Records committed_at" per spec §7.11, and nothing else in the flow can hold that
// timestamp) are modeled here. Anything screens 9-13 need that's purely local to their own screen
// (e.g. "did the user tap Allow on the notification prompt") belongs in that screen's own `@State`,
// not here — CLAUDE.md: "Don't add abstractions... beyond what the current session's scope
// requires." If a later screen turns out to need a new shared field, that's a follow-up patch to
// this file, not a reason for onboarding-2 to work around it.
//
// Persistence: this type is transient, in-memory UI state for the ~3-minute onboarding flow only
// (spec §7: "under 3 minutes"). Nothing here is a SwiftData `@Model` and nothing here writes a
// `Goal` / `User` / `GoalEvent` / `LockSet` row directly — turning these answers into real `Goal`
// rows (e.g. a workout goal from Q1/Q4), a `User.coachVoice` (from Q6), and a default `LockSet`
// (from Q2's `selectedApps`, via `LockSetManager.createLockSet(name:selection:)`) is Plan Reveal's
// job (screen 10, spec §7.10 "Your Lock-In Plan"), owned by onboarding-2 — this file only collects
// the raw answers.
//
// TODO(cross-module, future session): §9.2 Slip Prediction reads "historical miss pattern from
// onboarding Q5" as a cold-start ML feature, and §13's data model is meant to mirror whatever the
// client persists. That implies `MainGoal`/`FallOffPattern` below may eventually belong in `Core`
// so the Sync module and backend can share their raw values instead of Plan Reveal re-deriving
// equivalent Core-side types from these. Not done here: Core cannot import an App-target file, and
// moving these enums into Core is out of this session's owned file list — flagged for whichever
// session builds Sync's outbox payload for onboarding answers (spec §17 row 7).

import Foundation
import Observation
import FamilyControls
import Core

/// The full 14-screen onboarding flow's shared state machine (spec §7). A single instance is
/// expected to be created once per onboarding attempt (by whatever root/coordinator view hosts
/// the flow — outside this session's owned files) and threaded to every screen via `@Bindable`.
@MainActor
@Observable
final class OnboardingFlowState {

    /// Spec §7's first screen number (Hook).
    static let firstScreen = 1
    /// Spec §7's last screen number (First win).
    static let lastScreen = 14

    /// 1-indexed, matching spec §7's own screen numbering exactly (see file header table).
    var currentScreen: Int = 1

    // MARK: - Q1-Q6 answers (spec §7.3-§7.8)

    /// Q1 (screen 3): "Get consistent at the gym / Hit my protein / Stop doomscrolling / Lock in
    /// on work-school / All of it" (spec §7.3). `nil` until the user picks one.
    var mainGoal: MainGoal?

    /// Q2 (screen 4): the FamilyControls selection from the onboarding-embedded
    /// `FamilyActivityPicker` (spec §7.4). Device-local only, same rule as
    /// `LockSet.appTokensBlob` (`Core/Sources/Core/Models/LockSet.swift`) — never synced, never
    /// logged. Plan Reveal (screen 10) is expected to hand this straight to
    /// `LockSetManager.createLockSet(name:selection:)` to become the user's default lock set.
    var selectedApps = FamilyActivitySelection()

    /// Q3 (screen 5): daily phone time in hours, slider range 1...10 (spec §7.5).
    var dailyPhoneTimeHours: Double = 5

    /// Q4 (screen 6), first stepper: current workouts/week (spec §7.6).
    var currentWorkoutsPerWeek: Int = 0

    /// Q4 (screen 6), second stepper: target workouts/week (spec §7.6). Additive-goals-only
    /// (spec §3, §24) — always >= 1; there is no "0" target because a workout goal that asks for
    /// zero workouts isn't a goal.
    var targetWorkoutsPerWeek: Int = 3

    /// Q5 (screen 7): "Weekends / Evenings / When stressed / After a few good days / Travel"
    /// (spec §7.7). Feeds §9.2 Slip Prediction's cold start. `nil` until the user picks one.
    var fallOffPattern: FallOffPattern?

    /// Q6 (screen 8): coach voice (spec §5.13, §7.8). Defaults to `.hype`, matching
    /// `SharedDefaults.coachVoice`'s and `User.coachVoice`'s own documented defaults.
    var coachVoice: CoachVoice = .hype

    // MARK: - Screen 11: Commitment (spec §7.11)

    /// "Records `committed_at`" (spec §7.11) — the moment the user completed the 2-second
    /// hold-to-commit gesture. `nil` until screen 11 (onboarding-2) sets it via
    /// `recordCommitment()`. Nothing before screen 11 should set this.
    private(set) var committedAt: Date?

    init() {}

    // MARK: - Navigation

    /// Moves to the next screen, clamped at `lastScreen`. Screens are responsible for their own
    /// per-screen validation (e.g. disabling their Continue button while `mainGoal == nil`)
    /// before calling this — this method intentionally does not re-validate, so it stays a plain,
    /// unconditional "go forward one" that works the same for every screen, including the ones
    /// this file doesn't otherwise know about (screens 9-14).
    func advance() {
        guard currentScreen < Self.lastScreen else { return }
        currentScreen += 1
    }

    /// Moves to the previous screen, clamped at `firstScreen`.
    func goBack() {
        guard currentScreen > Self.firstScreen else { return }
        currentScreen -= 1
    }

    /// `currentScreen` as a 0...1 fraction of the full flow, for any shared progress chrome
    /// (e.g. a progress bar in the container that hosts every screen).
    var progressFraction: Double {
        Double(currentScreen) / Double(Self.lastScreen)
    }

    /// Records the commitment timestamp (spec §7.11). Calling it again overwrites with the
    /// latest hold, which only matters if a screen ever re-presents itself after the fact (e.g.
    /// the user backs up and re-commits) — the most recent real hold always wins, never a stale
    /// one.
    func recordCommitment(at date: Date = .now) {
        committedAt = date
    }

    // MARK: - Derived (screen 9: Wake-up moment, spec §7.9)

    /// Spec §7.9's own worked example: "At 5h/day, that's ~76 days a year on your phone." —
    /// `dailyPhoneTimeHours * 365 / 24`, exposed here so onboarding-2 doesn't have to re-derive
    /// the same arithmetic from a raw stored hour value.
    var estimatedDaysPerYearOnPhone: Double {
        dailyPhoneTimeHours * 365 / 24
    }
}

// MARK: - MainGoal (Q1, spec §7.3)

/// Copy note: this file (App target) cannot route these option labels through
/// `Core/Sources/Core/Copy` the way every other user-facing string in this session's screens does
/// — `Copy` lives in the `Core` package, which `App` depends on, not the reverse, so Core cannot
/// reference an App-only type like this enum. `displayLabel` below is a deliberate, narrow
/// exception to CLAUDE.md's "no hardcoded strings outside Copy" rule, scoped to exactly these two
/// onboarding-only enums (see `FallOffPattern` below), and reproduces spec §7.3's option list
/// verbatim.
enum MainGoal: String, CaseIterable, Sendable, Hashable {
    case gymConsistency
    case protein
    case stopDoomscrolling
    case lockInWorkSchool
    case allOfIt

    /// Verbatim option labels from spec §7.3.
    var displayLabel: String {
        switch self {
        case .gymConsistency: "Get consistent at the gym"
        case .protein: "Hit my protein"
        case .stopDoomscrolling: "Stop doomscrolling"
        case .lockInWorkSchool: "Lock in on work-school"
        case .allOfIt: "All of it"
        }
    }
}

// MARK: - FallOffPattern (Q5, spec §7.7)

/// See `MainGoal`'s doc comment above for why `displayLabel` is inline here rather than routed
/// through `Core/Sources/Core/Copy`.
enum FallOffPattern: String, CaseIterable, Sendable, Hashable {
    case weekends
    case evenings
    case whenStressed
    case afterGoodDays
    case travel

    /// Verbatim option labels from spec §7.7.
    var displayLabel: String {
        switch self {
        case .weekends: "Weekends"
        case .evenings: "Evenings"
        case .whenStressed: "When stressed"
        case .afterGoodDays: "After a few good days"
        case .travel: "Travel"
        }
    }
}
