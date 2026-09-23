// OnboardingDripCopy.swift
// Core / Copy
//
// User-facing copy for the post-onboarding drip pushes (docs/spec.md §7, last line: "Post-
// onboarding drip (Day 0-3 pushes): widget added? gym saved? NFC tag ordered/created? first squad
// invite?"). Per CLAUDE.md ("User-facing copy in Core/Sources/Core/Copy under the Copy.<area>
// umbrella pattern") and this codebase's established convention (`SunriseAlarmCopy`, `ShieldCopy`),
// `Core/Sources/Core/Social/OnboardingDripScheduler.swift` never builds a notification title/body
// itself — it calls into `Copy.onboardingDrip` and renders whatever comes back.
//
// Voice-aware (docs/spec.md §5.13: Hype / Tough Love / Chill / Data) — these are exactly the kind
// of "add real texture" moment `SunriseAlarmCopy`'s header contrasts with its own voice-invariant
// safety strings: a drip reminder about a skipped setup step has no safety/wayfinding stakes, so it
// should sound like the user's actual chosen coach, matching `CoachVoiceTone`'s established
// per-voice branching style (`Core/Sources/Core/Copy/CoachVoice.swift`, same directory). Keyed by
// `NudgeTone` (`Core/Sources/Core/Models/Nudge.swift`), not `CoachVoice` — that's the type
// `OnboardingDripScheduler` actually has in hand (it builds a `NudgeArm` to call `NudgeSender`
// with); `NudgeTone`'s own doc comment confirms its 4 raw values are intentionally identical to
// `CoachVoice`'s, so there is no meaning lost picking copy by one instead of the other.
//
// Every string here names something the user can fix in under a minute and never repeats — each
// condition is nudged at most once (`OnboardingDripScheduler`'s own idempotency guard) — so none of
// this needs spec §8 rule 9's "no shame" escape hatches the way a missed-goal notification would;
// there is no failure being described, only an unfinished setup step.

import Foundation

extension Copy {
    public enum onboardingDrip {

        /// docs/spec.md §7: "widget added?" — the user never added a Home Screen/Lock Screen
        /// widget after being prompted for one in onboarding screen 14.
        public static func widgetNotAdded(tone: NudgeTone) -> (title: String, body: String) {
            switch tone {
            case .hype:
                ("Add your widget — 2 taps", "See your streak and Today's Plan right on your Home Screen. Let's set it up!")
            case .toughLove:
                ("Still no widget", "You skipped it during setup. Add it now — it's the whole point of a Home Screen.")
            case .chill:
                ("No rush, but...", "Adding the ZANO widget makes checking in way easier. Whenever you've got a sec.")
            case .data:
                ("Widget: not installed", "Users with the widget open ZANO 2x more often. Takes under a minute to add.")
            }
        }

        /// docs/spec.md §7: "gym saved?" — no confirmed `Gym` row yet, so the Workout goal's Tier A
        /// geofence+dwell verification (spec §3) has nothing to check against.
        public static func gymNotSaved(tone: NudgeTone) -> (title: String, body: String) {
            switch tone {
            case .hype:
                ("Save your gym — let's go!", "Set your gym so ZANO can verify workouts automatically. No more manual logging.")
            case .toughLove:
                ("You haven't saved a gym yet", "Verification needs to know where you train. Set it up — 30 seconds.")
            case .chill:
                ("Set your gym whenever", "Once it's saved, workouts verify themselves — one less thing to think about.")
            case .data:
                ("Gym: not set", "Workout goals need a saved gym to auto-verify. 0 saved so far.")
            }
        }

        /// docs/spec.md §7: "NFC tag ordered/created?" — no saved `NFCTagMapping` yet, so nothing
        /// is mapped for a physical Tag Pack tap to trigger.
        public static func nfcTagNotCreated(tone: NudgeTone) -> (title: String, body: String) {
            switch tone {
            case .hype:
                ("Map your first NFC tag!", "Stick a tag on your bottle or desk — tap it, and ZANO just knows. Set one up.")
            case .toughLove:
                ("No tags mapped yet", "A tapped tag beats a typed log every time. Set one up.")
            case .chill:
                ("Tags make logging easier", "Whenever you're ready, map an NFC tag to skip typing things in.")
            case .data:
                ("NFC tags mapped: 0", "Tag taps log faster than manual entry. Map your first one.")
            }
        }

        /// docs/spec.md §7: "first squad invite?" — the user hasn't joined or started a squad yet
        /// (spec §5.7).
        public static func noSquadYet(tone: NudgeTone) -> (title: String, body: String) {
            switch tone {
            case .hype:
                ("Bring a friend into this!", "Squads make it way more fun — invite someone or join one now.")
            case .toughLove:
                ("You're doing this alone", "Squads keep you honest. Get one going.")
            case .chill:
                ("No pressure, but a squad helps", "Whenever you feel like it — a squad makes showing up easier.")
            case .data:
                ("Squad: none", "Users in a squad complete goals more consistently. Join or start one.")
            }
        }
    }
}
