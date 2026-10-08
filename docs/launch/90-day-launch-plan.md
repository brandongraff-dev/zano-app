# ZANO 90-day launch plan (Oct 12, 2026 – Jan 9, 2027)

Builds on `docs/spec.md` §22 (Launch & Content Plan), §21 (Monetization) and §23 (Metrics).
Revenue model: `docs/launch/model.js` (run `node docs/launch/model.js base|conservative|strong`).
Written 2026-10-08. Every money figure below comes from the model's assumptions. None of it is a forecast.
Replace the assumptions with real numbers from TestFlight and the first launch weeks as soon as you have them.

## The one-paragraph version

Pay creators a **share of the revenue they bring in**, not per video. That way an ad that flops costs
nothing, and you can afford to run hundreds of them. Your own accounts and rev-share creators carry the
first two months. Apple pays roughly two months after a sale, so **reinvested money only starts working
from February.** From then on, the profit from proven winners buys paid boosts, but only while a paid
install costs less than an install earns. Launch by Dec 1 so the January "lock in" spike lands on a live
app. Before any of this can happen, Apple Developer enrollment and the Family Controls entitlement have to go through.

## Critical path (nothing ships without these)

| By | What | Why |
|---|---|---|
| Oct 12 | Enroll in the Apple Developer Program ($99/yr) | Blocks TestFlight, the App Store listing and the entitlement request |
| Day enrollment clears | File all 4 Family Controls distribution entitlement requests (§24) | Approval can take days to weeks. Without it, the app can't use Screen Time in a store build |
| Nov 1 | RevenueCat + App Store Connect products (§21 plans) + paywall live in TestFlight | You can't attribute or pay creators without purchase events |
| Nov 1 | Affiliate tracking connected to RevenueCat (see "Paying creators") | Every creator needs their own link or code before posting |
| Dec 1 | **App Store launch** | Gives reviews and ranking 4 weeks to build before Jan 1 |

If the entitlement hasn't come back by **Nov 20**, keep building the waitlist and launch the day it's approved.
Fresh-start demand holds through mid-February, so a January launch still works. A launch after that
loses the biggest month of the year.

## Phase 1: Days 1–30 (Oct 12 – Nov 10). Audience before app

Goal: 3 content accounts posting daily, 1,000+ waitlist signups, 30 creators recruited.

- **Accounts (3).** (1) Founder build-in-public: "Day N of building the app that won't let me open TikTok
  until I hit the gym." (2) A faceless account: screen recordings of the shield and TikTok photo-carousel
  slideshows ("5 apps that fixed my discipline", with ZANO as one of them). (3) Gym POV: phone in a locker,
  workout, the unlock. Each posts 1–3 times a day on TikTok, Instagram Reels and YouTube Shorts, 3–9 posts a day in total.
- **Hooks.** Make 5 variations of each hook in §22, plus "my screen time went from 9h to 2h", "POV: you have to
  earn TikTok", "I gave my phone a gym buddy" and a buddy-mascot reveal. Change the first 2 seconds and the
  on-screen text, and keep the rest of the video the same.
- **Waitlist page.** One page, one field (email), one line ("TikTok unlocks after your workout"), linked from every bio.
  Ask "What app eats your day?" after signup. The answers become hooks.
- **Founding Creator program.** DM 20 creators a day with 2k–100k followers in gym, discipline, study-with-me,
  "dopamine detox" and screen-time niches. The offer is in "Paying creators" below. Aim for 30 signed and posting by Dec 1.
- **Product work that drives sharing (§5.16, §5.27, §5.14).** Locked Out card, Earned It clip and Weekly Report Card,
  all 9:16 with the zano name. Moving these from v2 into the launch build is a scope change, so get the founder's
  sign-off and update §17 first.

## Phase 2: Days 31–60 (Nov 11 – Dec 10). TestFlight, then launch

Goal: 100–200 TestFlight users, 10 real quotes, launch Dec 1, 20+ ads live per week.

- **TestFlight** to the first 200 people on the waitlist. Measure the §23 funnel: onboarding completion, paywall start
  rate, first earned unlock. **The paywall start rate is the most important number in the model.** At 5%, paid ads can't
  make money (see the model). At 8% or more, they can.
- **App Store page.** First screenshot: the shield ("TikTok unlocks after your workout · Streak 14"). Subtitle aimed at
  "app blocker", "screen time" and "gym". The preview video is the best-performing organic clip.
- **Launch week (Dec 1–7).** All 30 founding creators post that week. You post 3 times a day per account.
  Email the waitlist. Ask for an App Store rating after the first earned unlock (Apple shows that prompt at most 3 times a year).
- **App Store offer codes for creators.** Each creator gets a code for a longer trial (14 days instead of 7). It gives
  viewers a reason to use the creator's code, and attribution comes free. Unverified: confirm in App Store Connect
  that subscription offer codes work with RevenueCat in your setup.

## Phase 3: Days 61–90 (Dec 11 – Jan 9). The January push

Goal: 30–60 creators active, 40+ new ads a week, January Lock-In challenge live.

- **"January Lock-In" monthly challenge (§5.9)** goes live Dec 26. Content shifts to "Starting Jan 1, my phone makes me earn it."
- **Testing system** (below) runs every week. The best 10% of ads get boosted. The rest stop at 48 hours.
- **First paid money arrives in February** (Apple's payout lag). Until then, any cash spent on boosts comes from the starting budget.
- **Day 90 review:** compare actual numbers with the model, put the real ones into `model.js`, and plan days 91–180.

## Paying creators: revenue share, not per video

**Structure (recommended):**

- **Founding Creators (first 30):** **35% of net revenue** from every subscriber they bring in, for **12 months**.
  "Net" means after Apple's 15% and refunds. They also get a free year of ZANO and a milestone bonus
  (e.g. $100 at 100 paying subscribers) once that revenue has actually reached you.
- **Everyone after that: 25% for 12 months.** Keep the 35% rate for anyone who brings in 50+ subscribers a month.
- **Payouts:** monthly, only for revenue Apple has actually paid you, so roughly 2 months after the sale.
  Refunded subscriptions are clawed back. State all of this in a one-page creator agreement.
- **Why it beats per-video pay at your budget:** a video that gets 300 views costs $0. You can let 50 creators post
  as much as they want, and the ones who sell earn the most and post more. The trade-off is that creators with big
  audiences rarely take pure rev-share from an unknown app. So recruit hungry small and mid-size creators, and show
  them their earnings dashboard.

**Tools (check current prices and terms before signing up; these came from 2026 web sources, not tested):**

| Tool | What it does | Cost (as reported) | Use it for |
|---|---|---|---|
| [Insert Affiliate](https://www.capterra.com/p/10049513/Insert-Affiliate/) | Tracks affiliate links/codes to in-app subscriptions through a RevenueCat webhook, pays out through Stripe Connect | From ~$50/mo flat, no transaction fee (Capterra) | **Core rev-share tracking and payouts** |
| GoMarketMe | Similar app-affiliate tracking, applies offer codes for referred users | Price not found | Alternative to Insert Affiliate |
| [Whop Content Rewards](https://docs.whop.com/memberships-and-access/third-party-apps/content-rewards) | Clippers post your clips, and you pay **per 1,000 views** from a budget you set | ~$1 CPM is typical, plus a ~10% fee; payouts held ~10 days | **Paid boosts on proven winners only.** It pays per view, not per sale, so cap it |
| TikTok Spark Ads | Boost an organic post (yours or a creator's, with their code) | Pay per impression | Paid boosts on proven winners only |
| Apple Search Ads | Bids on App Store searches | Pay per tap | Once you have 4.5★ and 50+ ratings: bid on your own name and competitor names |
| "Tybe" / Trybe | Couldn't verify. The closest match is a UGC creator app (Trybe/Tribe, ~March 2026) where some brands pay a % of sales, from a single video source | Unknown | Check its terms. If it offers % of revenue with in-app subscription tracking, it fits this plan |

## Testing system: run lots of ads, cut the losers fast

The rule: **ideas are cheap and data decides.** Each week:

1. **Make 20–40 new posts** (your accounts plus creators), each testing one change: hook, first frame,
   on-screen text, format (talking head, POV, slideshow, screen recording) or ending.
2. **48-hour cut:** a post under **1,000 views** or under **1 install per 1,000 views** (from creator codes plus
   "Where did you hear about us?") is dead. Don't boost it and don't remake it.
3. **Winner:** over **10k views and over 1.5 installs per 1,000 views**. Make 5 remixes the next day
   (same idea, new hook or face) and give it a **$20 boost test** on Spark Ads or Whop.
4. **Keep boosting only while CPI stays below revenue per install** (about $1.12 in the base case, see the model).
   When CPI goes above that, stop: each further install loses money in its first year.
5. **Every Monday:** write the top 3 and bottom 3 posts and why in a shared sheet, then feed the winning hooks to every creator.

Expect roughly **1 post in 10** to beat its account's average and **1 in 50** to really take off. That's why volume matters more than polish.

## The reinvestment loop: how the money works

```
creator + organic posts ──► installs ──► trials ──► paying subscribers
        ▲                                                │
        │                              Apple pays ~2 months later (net of 15%)
        │                                                │
        │                    ┌───── 25–35% to the creator who brought them
        │                    ├───── 20% set aside for taxes
        └── paid boosts ◄────┴───── rest: boost winners while CPI < revenue per install
                                    (anything left over is your profit)
```

Three things decide whether it compounds:

1. **Revenue per install** = paywall start rate × what a paywall start is worth, after Apple's cut and refunds.
   Base case: 8% × $14.0 ≈ **$1.12**. This is the most a paid install may cost.
2. **Cost per install of winners.** Boosted winners land around $0.80–$1.50 in the model's scenarios. Below revenue
   per install the loop grows. Above it, paid spend shrinks your cash, so stop and put the effort into organic and creators.
3. **Payout lag.** Apple pays about 33 days after its fiscal month closes, so December sales arrive in early February.
   With a $500 start, the loop can't speed up until February. That's why organic and rev-share (both about $0 upfront)
   have to carry December and January.

## What the model says (assumptions, not promises)

Starting cash $500, $250 pre-launch costs, $120/mo tools, 25% creator share, 20% tax reserve, 100% of the rest
reinvested within the kill rule. Prices from §21: $39.99/yr (75% of trial starts), $69.99/yr family (5%), $6.99/mo (20%).

| June 2027 | Conservative | Base | Strong |
|---|---|---|---|
| Paywall start rate / trial→paid | 5% / 30% | 8% / 35% | 12% / 40% |
| Downloads per day (June) | ~58 | ~283 | ~1,158 |
| Net revenue earned in June | ~$970 | ~$8,500 | ~$57,000 |
| Paying subscribers | ~130 | ~1,070 | ~6,550 |
| Yearly value of the subscriber base (after Apple) | ~$6.3k | ~$50k | ~$302k |
| Paid boosts allowed? | No (CPI $1.50 > $0.63 per install) | Yes, capped ~$2.4k/mo | Yes, $25k/mo by June |

How to read it:

- **1,000 downloads a day is reachable by month 6–7 only in the strong case.** That needs a paywall start rate of ~12%,
  40+ active creators and an organic account that keeps compounding. In the base case you reach about 250–300 a day.
- **The cheapest way up the table is the paywall start rate,** not more ads. Going from 5% to 8% turns paid ads from
  losing money into making money. Run the §23 paywall experiments in TestFlight before spending anything on ads.
- **Cash looks small even when the business is growing,** because the model reinvests everything. The "yearly value
  of the subscriber base" row shows what you're building. Annual renewals (from Dec 2027) aren't in the model.

## Model assumptions (change these when real data arrives)

| Assumption | Base value | Where it comes from |
|---|---|---|
| Installs per 1,000 organic views | 1.2 | Rule of thumb for app content (0.1–0.5% of views). Unverified |
| Paywall start rate (install → trial or monthly) | 8% | Hard paywall. The RevenueCat 2026 Health & Fitness median install→trial is reported at 6.9% and the top apps above 23% (secondary sources) |
| Trial → paid | 35% | RevenueCat 2026 reports ~37% for 5–9 day trials; Adapty 2026 ~35% for Health & Fitness (secondary sources) |
| Apple's cut | 15% | App Store Small Business Program (under $1M/yr). You must enroll in it |
| Payout lag | 2 months | Apple pays ~33 days after the fiscal month closes |
| Monthly plan retention | 75%/mo | Typical for consumer subscriptions. Unverified |
| Word of mouth | +10% installs | Share cards, referrals, gym spread (§5.8) |
| January boost | 1.6× | New Year fresh-start demand. Unverified for this app |
| Creators | 10 at launch, +15 a month, ~30k views each per month on average | Most will get little. A few carry the average |

## Weekly scoreboard (every Monday)

Posts made · total views · installs per 1k views · paywall start rate · trial→paid · active creators ·
creator payouts owed · boost spend · CPI of boosted winners vs revenue per install · cash · tax reserve.
