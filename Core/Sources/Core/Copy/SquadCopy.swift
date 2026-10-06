// SquadCopy.swift
// Core / Copy
//
// `Copy.squad` — every user-facing string in `App/ZANO/Features/Squad/` (the Squad tab: squads,
// ring board, nudges, duels, "Beat last week"). docs/spec.md §5.7 (Squads & Duels), §5.4 (Ghost
// Mode, which the solo duel builds on), §8 rule 7 (nudge cap) and rule 9 (no shame: a lost duel is
// "slipped", never "failed").
//
// Honesty rule for this area: the squad backend isn't live yet, so every string that describes a
// network-only feature says so plainly ("goes live soon", "needs squads to be live") instead of
// pretending something was delivered.

import Foundation

extension Copy {
    public enum squad {
        // MARK: Tab

        public static let screenTitle = "Squad"

        // MARK: Status capsules

        public static let liveStatus = "Squads live"
        public static let offlineStatus = "Squads go live soon"
        public static let localOnlyStatus = "Saved on this phone"

        // MARK: Hero (no squad yet)

        public static let heroEyebrow = "Squads"
        public static let heroTitle = "Lock in together."
        public static let heroBody =
            "Bring 3 to 6 friends (up to 8). See each other's rings every day, nudge whoever's slipping, and settle it with a 7-day duel."
        public static let heroPointRings = "Everyone's daily rings, side by side"
        public static let heroPointNudge = "One-tap nudges, max 2 a day per friend"
        public static let heroPointDuel = "7-day duels, a point per verified goal"
        public static let heroPointFreeze = "One shared streak freeze a week"
        public static let createSquadButton = "Create a squad"
        public static let joinWithCodeButton = "Join with a code"

        // MARK: Offline ("goes live soon")

        public static let offlineTitle = "Squads go live soon"
        public static let offlineBody =
            "Friends can't join yet. You can still name your squad and reserve its invite code now. It's saved on this phone and goes live the moment squads do."
        public static let offlineRingsNote = "Squadmates' rings show up once squads are live."
        public static func offlinePendingJoin(_ code: String) -> String {
            "Code \(code) is saved. We'll join you automatically once squads are live."
        }
        public static let clearPendingJoin = "Forget this code"
        public static let needsNetworkBadge = "Needs squads live"

        // MARK: Squad home (in a squad)

        public static let weeklyRingTitle = "This week"
        public static func weeklyRingValue(percent: Int) -> String { "\(percent)%" }
        public static func weeklyRingCaption(members: Int) -> String {
            members == 1 ? "Just you so far" : "\(members) members"
        }
        public static func weeklyRingAccessibility(_ percent: Int) -> String { "Squad weekly ring, \(percent) percent" }
        public static let boardSectionTitle = "Rings"
        public static let duelsSectionTitle = "Duels"
        public static let inviteSectionTitle = "Invite"
        public static let freezeSectionTitle = "Shared freeze"
        public static let freezeAvailable = "Available this week. If anyone slips, one freeze covers the whole squad."
        public static func freezeUsed(by name: String) -> String { "Used this week by \(name). Resets Monday." }

        public static let youName = "You"
        public static func memberName(index: Int) -> String { "Squadmate \(index)" }
        public static let ownerBadge = "Owner"
        public static let lockedBadge = "Locked"
        public static let unlockedBadge = "Unlocked"
        public static let lockUnknown = "Lock status syncs"
        public static func starsLabel(_ count: Int) -> String { "\(count)" }
        public static func starsAccessibility(_ count: Int) -> String {
            "\(count) full \(count == 1 ? "day" : "days") this week"
        }
        public static func streakLabel(_ days: Int) -> String { "\(days)d" }
        public static func streakAccessibility(_ days: Int) -> String { "\(days) day streak" }
        public static let ringsPendingSync = "Rings sync when squads are live"
        public static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
        public static func dayRingAccessibility(day: String, completed: Int, total: Int) -> String {
            "\(day): \(completed) of \(total) goals"
        }
        public static let aloneTitle = "It's just you in here"
        public static let aloneBody = "Share your invite code. Squads work best with 3 to 6 people."

        // MARK: Nudge

        public static let nudgeButton = "Nudge"
        public static func nudgeAccessibility(name: String) -> String { "Nudge \(name)" }
        public static func nudgesLeft(_ n: Int) -> String { n == 1 ? "1 left today" : "\(n) left today" }
        public static let nudgeCapReached = "2 nudges sent today. Try tomorrow."
        public static let nudgeCooldown = "Just nudged. Give them a minute."
        public static let nudgeSent = "Nudge sent."
        public static let nudgeQueued = "Nudge saved. It sends once squads are live."
        public static let nudgeFailed = "Couldn't send that nudge."

        // MARK: Invite / share

        public static let inviteCodeLabel = "Invite code"
        public static let copyCode = "Copy code"
        public static let copiedCode = "Copied"
        public static let shareInvite = "Share invite"
        public static func shareMessage(squadName: String, code: String, link: String) -> String {
            "Join my squad \"\(squadName)\" on ZANO. Tap \(link) or open ZANO → Squad → Join with a code and enter \(code)."
        }
        public static func sharePreviewTitle(squadName: String) -> String { "Join \(squadName) on ZANO" }
        public static let inviteOfflineNote = "Your code is reserved. Friends can use it once squads go live."

        // MARK: Leave

        public static let menuAccessibility = "Squad options"
        public static let leaveSquad = "Leave squad"
        public static let leaveConfirmTitle = "Leave this squad?"
        public static let leaveConfirmMessage = "You can rejoin later with the invite code."
        public static let leaveConfirmButton = "Leave"
        public static let cancel = "Cancel"
        public static let done = "Done"

        // MARK: Create / join sheet

        public static let createTab = "Create"
        public static let joinTab = "Join"
        public static let createTitle = "New squad"
        public static let nameFieldLabel = "Squad name"
        public static let namePlaceholder = "5 AM Club"
        public static let emojiLabel = "Emblem"
        public static let colorLabel = "Color"
        public static let createButton = "Create squad"
        public static let createOfflineButton = "Reserve my code"
        public static let createdTitle = "Your squad is ready"
        public static let createdOfflineTitle = "Code reserved"
        public static let createdBody = "Send this code to 3 to 6 friends. It's the only way in."
        public static let joinTitle = "Join a squad"
        public static let joinBody = "Enter the 6-character code a friend sent you."
        public static let codeFieldLabel = "Invite code"
        public static let codePlaceholder = "ABC234"
        public static let joinButton = "Join squad"
        public static let joinOfflineButton = "Save code for later"
        public static let joinOfflineNote = "Joining someone else's squad needs squads to be live. We'll save the code and join you then."
        public static func joinedTitle(squadName: String) -> String { "You're in \(squadName)" }
        public static let joinedBody = "Your rings are on the squad board now. Go close one."


        // MARK: Errors (Copy for `SquadManagerError` / `DuelManagerError`)

        public static let errorNoUser = "Finish setting up ZANO first."
        public static let errorInvalidName = "Give your squad a name."
        public static let errorInvalidCode = "That code doesn't look right. Codes are 6 letters and numbers."
        public static let errorCodeNotFound = "No squad with that code. Check it with your friend."
        public static let errorSquadFull = "That squad is full (8 max)."
        public static let errorGeneric = "Something went wrong. Try again."

        // MARK: Duels list

        public static let duelsEmptyTitle = "No duels yet"
        public static let duelsEmptyBody = "Start with the one you can always play: beat last week."
        public static let newDuelButton = "Start a duel"
        public static let soloDuelRowTitle = "Beat last week"
        public static func soloDuelRowSubtitle(this: Int, last: Int) -> String { "\(this) vs \(last) at this point last week" }
        public static let worksOffline = "Works offline"
        public static func friendDuelRowTitle(name: String) -> String { "You vs \(name)" }
        public static let pendingStatus = "Waiting for them to accept"
        public static let activeStatus = "Live"
        public static let completeStatus = "Final"
        public static func scoreLine(me: Int, them: Int) -> String { "\(me) – \(them)" }

        // MARK: Duel invite sheet

        public static let inviteSheetTitle = "Start a duel"
        public static let inviteSheetBody = "7 days. One point per verified goal. Plan B counts. Nothing restrictive ever scores."
        public static let soloOptionTitle = "Beat last week"
        public static let soloOptionBody = "Race your own last week, day by day. No friends needed, works offline."
        public static let friendsSectionTitle = "Challenge a squadmate"
        public static let noSquadmates = "Once friends join your squad, you can challenge them here."
        public static let challengeButton = "Challenge"
        public static let challengeSent = "Challenge sent. It starts when they accept."
        public static let challengeOffline = "Head-to-head duels need squads to be live."

        // MARK: Duel view

        public static let duelTitle = "Duel"
        public static let soloDuelTitle = "Beat last week"
        public static let youLabel = "You"
        public static let lastWeekLabel = "Last week"
        public static let pointsUnit = "pts"
        public static let versus = "vs"
        public static func soloDayAccessibility(day: String, you: Int, lastWeek: Int) -> String {
            "\(day): you \(you), last week \(lastWeek)"
        }
        public static func countdown(days: Int, hours: Int) -> String {
            days > 0 ? "\(days)d \(hours)h left" : "\(hours)h left"
        }
        public static let endsSoon = "Ends within the hour"
        public static let pointsRule = "1 point per verified goal. Plan B counts."
        public static let dailyBreakdownTitle = "Day by day"
        public static func paceAhead(_ n: Int) -> String { "\(n) ahead of last week's pace" }
        public static func paceBehind(_ n: Int) -> String { "\(n) behind last week's pace. One goal closes the gap." }
        public static let paceTied = "Dead even with last week's pace"
        public static func toBeat(_ n: Int) -> String {
            n == 1 ? "1 more point beats last week" : "\(n) more points beat last week"
        }
        public static let beatenLastWeek = "Last week is beaten. Everything now is extra."
        public static let noLastWeek = "No points last week. Any verified goal wins this one."
        public static let lastWeekResultTitle = "Last week's result"
        public static func soloResult(won: Bool, tied: Bool, this: Int, previous: Int) -> String {
            if tied { return "Tied the week before, \(this) – \(previous)." }
            return won
                ? "You beat the week before, \(this) – \(previous)."
                : "The week before edged it, \(previous) – \(this). This week's a fresh race."
        }
        public static let resultWin = "You won"
        public static let resultLoss = "They took this one"
        public static let resultTie = "Dead heat"
        public static let resultSubtitleLoss = "Slipped by a little. Run it back."
        public static let pendingTitle = "Waiting on them"
        public static let pendingBody = "The 7 days start once they accept."
        public static let opponentScorePending = "Their score syncs once squads are live."
        public static let opponentScoreUnknown = "–"
        public static let rematch = "Rematch"
        public static let tauntNote = "Optional friendly taunt on the loser's shield comes with live squads."
    }
}
