// ZANO launch revenue model. Plain JS, no deps. Run: node docs/launch/model.js [conservative|base|strong]
// Every number here is an assumption (see docs/launch/90-day-launch-plan.md, "Model assumptions").
const MONTHS = ["Dec 2026", "Jan 2027", "Feb 2027", "Mar 2027", "Apr 2027", "May 2027", "Jun 2027"];
// New Year is the biggest month for "lock in" apps; December is gift/holiday-distracted.
const SEASON = [0.85, 1.6, 1.2, 1.0, 1.0, 0.95, 1.05];

const SCENARIOS = {
  conservative: { paywallStart: 0.05, trialToPaid: 0.30, organicViews: 200000, organicGrowth: 0.15, creatorsStart: 5, creatorsAdded: 8, viewsPerCreator: 20000, installsPer1k: 1.0, paidCPI: 1.5 },
  base:         { paywallStart: 0.08, trialToPaid: 0.35, organicViews: 400000, organicGrowth: 0.25, creatorsStart: 10, creatorsAdded: 15, viewsPerCreator: 30000, installsPer1k: 1.2, paidCPI: 1.0 },
  strong:       { paywallStart: 0.12, trialToPaid: 0.40, organicViews: 800000, organicGrowth: 0.35, creatorsStart: 15, creatorsAdded: 25, viewsPerCreator: 40000, installsPer1k: 1.5, paidCPI: 0.8 },
};

const DEFAULTS = {
  startCash: 500,          // what you launch with
  preLaunchCost: 250,      // Apple Developer $99 + domain + tag samples, spent Oct-Nov
  fixedMonthly: 120,       // affiliate tracking (~$50), Supabase/LLM/misc
  revShare: 0.25,          // % of net revenue paid to the creator who brought the user, 12 months
  reinvest: 1.0,           // share of free cash put into paid boosts each month
  taxReserve: 0.20,        // share of positive monthly cash flow parked for taxes, never spent
  cashBuffer: 200,         // never spend below this
  appleFee: 0.15,          // App Store Small Business Program (<$1M/yr)
  refunds: 0.04,
  payoutLagMonths: 2,      // Apple pays ~33 days after its fiscal month closes => ~2 calendar months
  wordOfMouth: 0.10,       // extra installs from share cards / referrals, as a share of all others
  monthlyRetention: 0.75,  // monthly-plan subscribers who renew each month
  mixAnnual: 0.75, mixFamily: 0.05, mixMonthly: 0.20,
  priceAnnual: 39.99, priceFamily: 69.99, priceMonthly: 6.99,
  cpiScale: 20000,         // CPI climbs as spend grows: cpi * (1 + spend / cpiScale); winners saturate
};

// First-year net revenue one install is worth (after Apple's cut and refunds). This is the
// most a paid install may cost: above it, every ad dollar loses money inside the first year.
function revenuePerInstall(p) {
  let monthlyFactor = 0;
  for (let k = 0; k < 12; k++) monthlyFactor += Math.pow(p.monthlyRetention, k);
  const perStart = p.mixAnnual * p.trialToPaid * p.priceAnnual + p.mixFamily * p.trialToPaid * p.priceFamily
    + p.mixMonthly * p.priceMonthly * monthlyFactor;
  return p.paywallStart * perStart * (1 - p.appleFee) * (1 - p.refunds);
}

function run(p) {
  const maxCPI = revenuePerInstall(p);
  // Kill rule: winners get boosted only while their cost per install stays under maxCPI.
  const spendCap = Math.max(0, p.cpiScale * (maxCPI / p.paidCPI - 1));
  const rows = [];
  let cash = p.startCash - p.preLaunchCost;
  let monthlySubs = 0, annualSubs = 0, taxBank = 0, cumNet = 0, cumSpend = 0, cumPayout = 0;
  const earnedNet = [], creatorShareOfRev = [];
  for (let m = 0; m < MONTHS.length; m++) {
    // Cash that lands this month: Apple's payout for revenue earned payoutLagMonths ago.
    const src = m - p.payoutLagMonths;
    const cashIn = src >= 0 ? earnedNet[src] : 0;
    const payout = src >= 0 ? earnedNet[src] * creatorShareOfRev[src] * p.revShare : 0;
    const opFlow = cashIn - payout - p.fixedMonthly;
    cash += opFlow;
    // Taxes come off the top of positive operating cash before anything is reinvested.
    if (opFlow > 0) { const t = opFlow * p.taxReserve; taxBank += t; cash -= t; }

    // Paid boosts (Whop CPM clipping + TikTok Spark Ads on proven winners), funded only from cash on hand,
    // and only up to the spend where CPI still beats revenue per install. Cash past that is profit.
    const spendable = Math.max(0, cash - p.cashBuffer);
    const paidSpend = Math.round(Math.min(spendable * p.reinvest, spendCap));
    cash -= paidSpend;
    const cpi = p.paidCPI * (1 + paidSpend / p.cpiScale);
    const paidInstalls = paidSpend / cpi;

    const days = 30.4;
    const organicInstalls = p.organicViews * Math.pow(1 + p.organicGrowth, m) / 1000 * p.installsPer1k * SEASON[m];
    const creators = p.creatorsStart + p.creatorsAdded * m;
    const creatorInstalls = creators * p.viewsPerCreator / 1000 * p.installsPer1k * SEASON[m];
    const wom = (organicInstalls + creatorInstalls + paidInstalls) * p.wordOfMouth;
    const installs = organicInstalls + creatorInstalls + paidInstalls + wom;

    const starts = installs * p.paywallStart;
    const newAnnual = starts * p.mixAnnual * p.trialToPaid;
    const newFamily = starts * p.mixFamily * p.trialToPaid;
    const newMonthly = starts * p.mixMonthly;
    monthlySubs = monthlySubs * p.monthlyRetention + newMonthly;

    const gross = newAnnual * p.priceAnnual + newFamily * p.priceFamily + monthlySubs * p.priceMonthly;
    const net = gross * (1 - p.appleFee) * (1 - p.refunds);
    earnedNet.push(net);
    creatorShareOfRev.push(creatorInstalls / installs);

    annualSubs += newAnnual + newFamily; // annual plans don't renew inside this 7-month window
    cumNet += net; cumSpend += paidSpend; cumPayout += payout;

    rows.push({
      month: MONTHS[m],
      perDay: { organic: (organicInstalls + wom * organicInstalls / (installs - wom)) / days,
                creators: (creatorInstalls + wom * creatorInstalls / (installs - wom)) / days,
                paid: (paidInstalls + wom * paidInstalls / (installs - wom)) / days },
      installs, downloadsPerDay: installs / days, creators,
      newPaying: newAnnual + newFamily + newMonthly, monthlySubs, payingSubs: annualSubs + monthlySubs,
      // Yearly revenue the current subscriber base is worth after Apple's cut, before creator shares.
      arr: (annualSubs * (p.mixAnnual * p.priceAnnual + p.mixFamily * p.priceFamily) / (p.mixAnnual + p.mixFamily) + monthlySubs * p.priceMonthly * 12) * (1 - p.appleFee),
      gross, net, cashIn, payout, paidSpend, cpi, cash, taxBank, cumNet,
    });
  }
  return rows;
}

if (typeof module !== "undefined") module.exports = { run, revenuePerInstall, SCENARIOS, DEFAULTS, MONTHS, SEASON };
if (typeof require !== "undefined" && require.main === module) {
  const name = process.argv[2] || "base";
  const rows = run({ ...DEFAULTS, ...SCENARIOS[name] });
  const f = (n) => Math.round(n).toLocaleString("en-US");
  const p = { ...DEFAULTS, ...SCENARIOS[name] };
  console.log(`scenario: ${name}  revenue/install: $${revenuePerInstall(p).toFixed(2)}  winner CPI: $${p.paidCPI}`);
  console.log("month      dl/day  installs  newPaying  gross$   net$earned  cashIn  creator$  ads$   cash   taxBank  subs   netARR");
  for (const r of rows) console.log([r.month.padEnd(9), f(r.downloadsPerDay).padStart(6), f(r.installs).padStart(8), f(r.newPaying).padStart(9), f(r.gross).padStart(7), f(r.net).padStart(10), f(r.cashIn).padStart(7), f(r.payout).padStart(8), f(r.paidSpend).padStart(6), f(r.cash).padStart(6), f(r.taxBank).padStart(7), f(r.payingSubs).padStart(5), f(r.arr).padStart(7)].join("  "));
}
