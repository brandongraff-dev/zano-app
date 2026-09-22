# ZANO Tag Pack — Supplier Spec Sheet

**Product 1 of 5 in the Physical Product Bridge.** Source of truth: `docs/spec.md` §25.0, §25.1, §25.5.
This document is written to be sent to a factory/sourcing contact largely as-is. Anything marked
**[CONFIRM]** is not locked in `spec.md` and needs a decision (from us) or a supplier recommendation
before the sample order goes out.

---

## 1. What we're ordering

One **Tag Pack** = 5x adhesive NFC tags + 1x folded setup/placement card, shrink-wrapped or bagged as
a single retail unit.

| Component | Qty per pack | Notes |
|---|---|---|
| NTAG215 adhesive tag | 5 | Each pre-programmed with a unique NDEF URI record — see §3 |
| Folded setup card | 1 | Placement guide + first-run instructions — see §4 |
| Poly bag or shrink wrap | 1 | Retail-ready outer packaging |

Target retail price: $14–19, or free with an annual subscription (spec §25.0). This is deliberately
the cheapest product in the lineup — it's the market test that runs *before* the Lock Card (§25.2)
exists, so keep the BOM simple and the run small.

---

## 2. Tag hardware spec

| Spec | Value |
|---|---|
| Chip | **NTAG215** (NXP or NXP-compatible) — 504 bytes user memory, required for the URL record + headroom |
| Format | ISO/IEC 14443 Type A, 13.56 MHz |
| Form factor | Adhesive sticker / label inlay |
| Diameter | 25mm round **[CONFIRM]** — industry-standard size for this chip; ask supplier for their standard tooling size before requesting a custom die-cut, since custom shapes raise MOQ and cost |
| Adhesive | Permanent, rated for the surfaces in §5 (glass/mirror, painted metal water bottle, plastic shaker, painted desk/laptop surface, nylon/canvas gym bag) — ask supplier for adhesive datasheet, not just "strong adhesive" |
| Read range (phone-to-tag) | Must work reliably through a phone case up to ~2mm and through the bottle/shaker wall it's stuck to — **test this in the sample run, do not take a spec-sheet number on faith** |
| Color/finish | White or branded-print face **[CONFIRM]** — see §6 for branding options |
| Programming | Factory-programmed (preferred) or shipped blank for us to write — see §3 for which |

**Not on-metal:** unlike the Lock Card (§25.2 of spec.md), these are standard tags on non-metal or
mixed surfaces, so a ferrite-backed / on-metal inlay is **not required** here. That requirement is
specific to the metal Lock Card and should not be quoted for this SKU — don't let a sourcing rep
upsell on-metal inlays for the Tag Pack.

---

## 3. NDEF data format

Each tag ships pre-written with a **single NDEF URI record**:

```
zano://tag/<uuid>
```

- `<uuid>` is a v4 UUID, **unique per physical tag** — no two tags in any pack, or across packs,
  share a UUID. This is what lets the app tell tags apart after a tap.
- One NDEF record per tag. No additional records (no vCard, no plain-text fallback record) unless a
  later session asks for one — extra records waste the 504-byte budget and complicate parsing.
- The app maps a scanned UUID to a user-chosen action (Sunrise, Bottle, etc.) in a single setup
  screen the first time each tag is tapped — the tag itself carries no meaning beyond its UUID until
  the user assigns one (spec §25.1: "app maps it to an action in one screen").
- **Write-protection:** tags should be locked (NDEF read-only / lock bit set) after programming, so a
  stray tap with a generic NFC-writing app can't overwrite the URI. Confirm the supplier can do this
  at time of programming, not as a separate step we do by hand.

### Who writes the UUIDs — two options, pick one before ordering

1. **Factory pre-programmed (preferred for MOQ ≥100):** we supply a CSV of 5×N unique UUIDs before
   the production run; factory programs and locks each tag, ideally laser-marks or barcodes the
   physical unit/pack for QC traceability back to the CSV row. Ask if they support this — many
   NFC-card factories do this routinely for access-control cards.
2. **Blank tags, programmed in-house:** cheaper unit cost, but every tag has to be individually
   tapped and written with our own app/tool before it goes in a pack — not realistic at >100-unit
   volume without dedicated fulfillment tooling. Fine for the sample run (§8) since we're hand-testing
   those anyway; not recommended for the production run.

---

## 4. Setup card — physical spec

A single small folded card that ships inside the pack and does two jobs: **branding** (this is the
object that sits in someone's kitchen/gym bag) and **instructions** (how to assign each tag).

| Spec | Value |
|---|---|
| Format | Bi-fold or tri-fold card **[CONFIRM which]** — bi-fold (single fold, 4 panels total) is
recommended as the simpler/cheaper default; confirm once the branding layout (§6) is designed |
| Flat size (bi-fold, before folding) | ~85mm × 110mm **[CONFIRM]** — sized to comfortably hold 5 tag
positions plus a cover panel; adjust to whatever the final layout needs |
| Stock | 300–350gsm coated card stock, matte or soft-touch finish |
| Print | Full color, both sides |
| Finish options (nice-to-have, cost-permitting) | Spot UV or foil on the logo, rounded corners |

### Fold layout (4 panels for a bi-fold)

| Panel | Content |
|---|---|
| **Front cover** | ZANO logo/wordmark, product name ("Tag Pack"), minimal — this is the panel visible
on a shelf/in a photo |
| **Inside left** | Short "how it works" — tap tag, app opens, assign it once. 2–3 sentences max. |
| **Inside right** | The 5 placement labels (§5) as a simple checklist/diagram — this is the panel the
tags are meant to sit against or near before the user peels and places them |
| **Back** | Store/support URL, QR code to app download or setup deep link, small-parts/choking
warning (§9), batch/lot code space for QC traceability |

---

## 5. The 5 placement labels

Each of the 5 tags in a pack maps to one fixed placement, per spec §25.0 and §25.1. These are the
labels to print on the card and, if space allows, as a small icon/sticker set next to where each tag
sits before peeling:

1. **Sunrise** — mirror (bathroom mirror; required for the Sunrise Alarm flow)
2. **Bottle** — water bottle
3. **Shaker** — protein shaker (spec calls this "Shaker/Protein" — "Shaker" is the card-facing short
   label)
4. **Desk** — desk/focus surface
5. **Gym bag** — gym bag

Print order on the card should match this list (it's the order referenced in spec §25.1), and each
tag's physical position in the blister/backing sheet should match its printed label 1:1 so there's no
ambiguity about which sticker is "Bottle" vs "Desk" once they're peeled off the backing.

---

## 6. Branding requirements

- **Logo:** ZANO logo/wordmark on the card front cover, minimum size TBD by print legibility at final
  card dimensions. **[CONFIRM — logo source file (vector, e.g. AI/SVG/EPS) and brand color values
  (hex/Pantone) are not yet in `spec.md` or this repo.** Do not send a supplier a screenshot or raster
  export as the production art file; get the vector source before final art goes to print. Flag this
  as an open item — someone needs to supply or point to the brand asset file before card artwork is
  finalized.
- **Tag face print:** at minimum, a small ZANO mark on each tag face (the tag itself is a brand
  surface in someone's home/gym bag per spec §25's framing — "tags are brand surfaces in people's
  kitchens and gym bags"). Full-color print on a 25mm circle is tight; a one- or two-color mark is
  more realistic and cheaper at low MOQ.
- **Tone:** the card is the object a new user's first NFC interaction with the brand runs through —
  keep copy short and confident, consistent with the coach-voice copy system in `Core/Sources/Core/Copy`
  (not touched by this spec sheet, referenced for tone only).
- **What NOT to send to a supplier yet:** final logo files and locked brand colors. Get a proof back
  from the supplier using placeholder/wordmark-only art if we need to move on tooling/quoting before
  final brand assets exist, but do not commit to a production print run on placeholder art.

---

## 7. Cost & MOQ targets

| Metric | Target | Source |
|---|---|---|
| COGS per pack (at MOQ) | **$1.00–1.80** | spec §25.0 |
| MOQ — tags | **100–500** | spec §25.5 ("tags can be as low as 100–500") |
| MOQ — card | Match tag MOQ; cards are cheap at low volume and shouldn't be the constraint |
| Sell price | $14–19, or free with annual plan | spec §25.0 |

Note the general MOQ guidance in spec §25.5 (500–1,000) is for **custom metal** components (Lock
Card, §25.2) — tags and this simple card fall under the lower 100–500 MOQ band and should be quoted
as such. Don't let a sourcing rep quote metal-tier MOQ/pricing against this SKU.

Get itemized quotes (tag unit cost, card unit cost, programming/lock-bit fee if separate, packaging)
rather than a single bundled per-pack number — it makes it possible to see which line item to
negotiate or cut if the $1.00–1.80 target is missed.

---

## 8. Sample-run checklist (do this before any production order)

Per spec §25.5: *"Always order a sample run (3–5 units, ~$50–150) and test NFC read range on a real
iPhone before committing."* Concretely, before placing a production order:

- [ ] Order **3–5 sample packs** (i.e., 3–5 full packs, 15–25 tags total) — budget **~$50–150** all-in
      including sample shipping (air, since it's a handful of units)
- [ ] Confirm tags arrive with correct NDEF URI (`zano://tag/<uuid>`), unique UUIDs, and locked
      (read-only) — verify with a generic NFC-reader app, not just by trusting the packing slip
- [ ] Test NFC read on a **real iPhone** (not simulator — Core NFC does not work in the Simulator,
      per `CLAUDE.md`), specifically:
  - [ ] Bare tag tap, no case
  - [ ] Tap through the phone case we expect users to actually have on
  - [ ] Tap once the tag is adhered to each of the 5 target surfaces (mirror, a real bottle, a real
        shaker, a desk/laptop lid material, gym bag fabric) — adhesion to fabric and read range
        through a curved bottle wall are the two likeliest failure points
  - [ ] Tap-to-open-app end-to-end: tag scan triggers the app's tag-mapping screen (§3), not just a
        raw NFC read in a generic reader app
- [ ] Check adhesive hold after 24–48 hours on each of the 5 target surfaces, including a shaker that
      gets washed
- [ ] Confirm the card folds cleanly, the placement labels (§5) are unambiguous next to their tag
      position, and the logo/print quality is acceptable
- [ ] **Only after all of the above pass:** place the production order (100–500 units per §7),
      factory-programmed per §3 option 1 if volume supports it
- [ ] If read range, adhesion, or print quality fail on the sample run, iterate with the supplier and
      re-sample — do not scale a failed sample into a production order to save time

### Lead times (spec §25.5, applies to the whole hardware line — plan the Tag Pack against these)

| Stage | Duration |
|---|---|
| Sampling | 2–4 weeks |
| Production | 3–5 weeks |
| Freight (air, for first runs) | 2–5 weeks |
| **Total, decision → doorstep** | **~10–12 weeks** |

Fulfillment: self-ship this first run (spec §25.5 — cheap, and unboxing quality stays in our control);
move to a 3PL only once volume makes self-shipping a bottleneck.

---

## 9. Compliance & labeling notes

- **FCC:** does not apply — these are passive NFC tags with no transmitter (spec §25.5). No FCC ID or
  certification needed for the tags themselves.
- **Small parts / choking warning:** standard consumer-product labeling applies. Include a small-parts
  warning on the card packaging (back panel, §4) — adhesive tags are small enough to be a choking
  hazard.
- **Adhesive/skin contact:** if any tag is intended for a surface a user might touch skin-to-adhesive
  during application, confirm the adhesive is a standard non-toxic label adhesive (should be default
  for any reputable NFC-tag manufacturer, but ask).
- No lithium battery or active RF component in this product — the "lithium battery shipping rules"
  caveat in spec §25.5 does not apply to the Tag Pack. (It will matter for any future active/Bluetooth
  hardware, not this SKU.)

---

## 10. Sourcing notes

- Primary channels: **Alibaba / 1688** (spec §25.5). Search for NFC sticker/label manufacturers who
  list NTAG215 explicitly, not just "NFC tag" — chip spec matters for the 504-byte NDEF payload.
- Ask every candidate supplier, up front, for:
  - NTAG215 confirmation (not NTAG213 — too little memory margin for future NDEF record additions;
    not NTAG216 — no need to pay for the extra memory)
  - Custom URI pre-programming + lock-bit capability (§3) and whether they can take a CSV of UUIDs
  - Adhesive datasheet for the surfaces in §5
  - Card printing capability (or point us to a separate card printer if tags and cards aren't one
    supplier — bundling both with one factory simplifies the sample-run logistics but isn't required)
  - Itemized quote per §7, at both 100-unit and 500-unit MOQ, so we can see the price curve
- Get photos of actual prior work (not stock renders) before committing to a sample order.

---

## Open items before this can go to a supplier as final art/spec

1. **[CONFIRM]** Brand asset file (vector logo, hex/Pantone colors) — not yet in the repo.
2. **[CONFIRM]** Bi-fold vs tri-fold card, and exact flat dimensions — depends on final card layout
   design.
3. **[CONFIRM]** Tag face print — full brand mark vs minimal one-color mark (cost tradeoff at low
   MOQ).
4. **Decision needed:** factory-programmed vs. in-house-programmed tags for the *production* run
   (§3) — sample run can use either, but production volume should settle this ahead of the order.

This spec sheet can go out for supplier quoting/sampling with items 1–3 as placeholders (use
wordmark-only or ZANO text mark as a stand-in), but **final production art requires item 1 resolved.**
