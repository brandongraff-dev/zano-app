// BuddyCopy.swift
// Core / Copy
//
// The buddies (mascot redesign, 2026-10-03): names, one-line descriptions, their worlds, and the
// picker's strings. See `Buddy`.

extension Copy {
    public enum buddy {
        public static func name(_ buddy: Buddy) -> String {
            switch buddy {
            case .stash: "Stash"
            case .zib: "Zib"
            case .lox: "Lox"
            case .pip: "Pip"
            case .moko: "Moko"
            case .brick: "Brick"
            case .tank: "Tank"
            case .volt: "Volt"
            case .howl: "Howl"
            }
        }

        /// What it is, in a few words.
        public static func kind(_ buddy: Buddy) -> String {
            switch buddy {
            case .stash: "Phone-hoarding raccoon"
            case .zib: "Star-antenna mochi bunny"
            case .lox: "Lock-fox with a keyhole tummy"
            case .pip: "Owl-axolotl with focus eyes"
            case .moko: "Hatchling dino that grows with you"
            case .brick: "Gym-rat bulldog in a sweatband"
            case .tank: "Gym rhino in a team jersey"
            case .volt: "Lightning shark"
            case .howl: "Night-run wolf in a hoodie"
            }
        }

        /// Its personality, one or two sentences.
        public static func line(_ buddy: Buddy) -> String {
            switch buddy {
            case .stash: "Cheeky and loyal. Stash hides your apps in its den and hands them back, no questions, once your goals are done."
            case .zib: "Soft, bouncy, a little dramatic. Zib keeps your apps in its pocket and gives them back the second you earn it."
            case .lox: "Quick and clever. Lox locks the door on doomscrolling and cheers when you walk back in."
            case .pip: "Calm and curious. Pip watches the clock in focus sessions and wiggles its gills when you finish."
            case .moko: "Sweet and always growing. Moko hatched on day one and grows with every day you show up."
            case .brick: "Loud, loyal, never skips leg day. Brick spots you through every goal."
            case .tank: "Big, calm, impossible to knock over. Tank charges through your goals and guards the gate."
            case .volt: "Fast and all charge. Volt eats distractions for breakfast and zaps the lock open when you win."
            case .howl: "Quiet focus, loud finishes. Howl runs the night trail with you and howls when you earn it."
            }
        }

        /// The buddy's world, shown as its theme name.
        public static func world(_ buddy: Buddy) -> String {
            switch buddy {
            case .stash: "The Den"
            case .zib: "Cloud Club"
            case .lox: "The Keyhole"
            case .pip: "Midnight Library"
            case .moko: "Hatch Valley"
            case .brick: "Iron Yard"
            case .tank: "Rock Canyon"
            case .volt: "Storm Reef"
            case .howl: "Night Trail"
            }
        }

        public static func crew(_ crew: Buddy.Crew) -> String {
            switch crew {
            case .cozy: "Cozy crew"
            case .hype: "Hype crew"
            }
        }

        public static let pickerTitle = "Pick your buddy"
        public static let pickerSubtitle = "They guard your apps and cheer your wins. Swap anytime in Settings."
        public static func teamUp(_ buddy: Buddy) -> String { "Team up with \(name(buddy))" }
        /// Settings row title.
        public static let settingsRow = "Buddy"
        /// VoiceOver for a picker tile: "Stash, phone-hoarding raccoon".
        public static func tileLabel(_ buddy: Buddy) -> String { "\(name(buddy)), \(kind(buddy))" }
        public static let selectedHint = "Selected"

        // MARK: - Today's hero (the buddy replaced the star, 2026-10-03)

        /// The hero's VoiceOver label on Today: the buddy's name and how it feels.
        public static func heroSpoken(_ buddy: Buddy, mood: ZanoMascotMood) -> String {
            let buddyName = name(buddy)
            return switch mood {
            case .sleepy: "\(buddyName), napping until a goal is done"
            case .idle: buddyName
            case .perky: "\(buddyName), warming up"
            case .charged: "\(buddyName), all done and happy"
            }
        }

        /// The hero's VoiceOver hint: what poking it does.
        public static let heroHint = "Makes your buddy spin"

        /// The picker's hero, spoken: "Stash. Phone-hoarding raccoon. The Den."
        public static func heroLabel(_ buddy: Buddy) -> String {
            "\(name(buddy)). \(kind(buddy)). \(world(buddy))."
        }

        // MARK: - Growth: level and gear (2026-10-03)

        public static func level(_ level: Int) -> String { "Lv \(level)" }
        public static func levelSpoken(_ level: Int) -> String { "Level \(level)" }
        /// "3 more earned unlocks to Lv 6".
        public static func toNextLevel(_ remaining: Int, next: Int) -> String {
            remaining == 1 ? "1 more earned unlock to Lv \(next)" : "\(remaining) more earned unlocks to Lv \(next)"
        }
        public static let maxLevel = "Max level. Legend status."
        public static let gearTitle = "Gear"
        public static let gearSubtitle = "Earned, never bought. Tap to wear."
        public static func gearName(_ gear: BuddyGear) -> String {
            switch gear {
            case .bare: "Nothing"
            case .partyHat: "Party hat"
            case .shades: "Shades"
            case .beanie: "Beanie"
            case .crown: "Crown"
            }
        }
        /// How to unlock it: "7-day streak".
        public static func gearRequirement(_ gear: BuddyGear) -> String {
            switch gear.requirement {
            case .none: ""
            case .earnedUnlocks(let count): count == 1 ? "First earned unlock" : "\(count) earned unlocks"
            case .bestStreak(let days): "\(days)-day streak"
            }
        }
        public static let gearWearing = "Wearing"
        public static let gearTapToWear = "Tap to wear"
        /// VoiceOver for a gear tile.
        public static func gearTileLabel(_ gear: BuddyGear, unlocked: Bool, wearing: Bool) -> String {
            if !unlocked { return "\(gearName(gear)), locked. Unlocks at \(gearRequirement(gear))." }
            return wearing ? "\(gearName(gear)), wearing" : gearName(gear)
        }
        /// Today's toast when new gear goes on: "Stash put on the shades! 7-day streak."
        public static func gearAdopted(_ buddy: Buddy, gear: BuddyGear) -> String {
            "\(name(buddy)) put on the \(gearName(gear).lowercased())! \(gearRequirement(gear))."
        }
        /// "Next: Beanie" and "9 of 14 days" under it.
        public static func nextGear(_ gear: BuddyGear) -> String { "Next: \(gearName(gear))" }
        public static func nextGearProgress(_ gear: BuddyGear, have: Int, need: Int) -> String {
            switch gear.requirement {
            case .earnedUnlocks: "\(have) of \(need) earned unlocks"
            case .bestStreak: "\(have) of \(need) streak days"
            case .none: ""
            }
        }
        public static let allGearUnlocked = "Every piece of gear unlocked. Legend."
    }
}
