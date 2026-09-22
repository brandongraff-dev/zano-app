# ZANO Lock Card — Supplier Spec Sheet

Status: **Draft — ready to send for factory quoting / sample run.**
Source of truth: `docs/spec.md` §25.2 (product design), §25.3 (Earned Cards program),
§25.5 (manufacturing & ops), §25.0 (COGS/price targets), §27 (NFC gotcha).
Sourcing channel: Alibaba / 1688 (metal card + on-metal NFC inlay manufacturers).

---

## 1. What this product is

A **metal fold-out phone stand with an embedded NFC tag**. Not a plain tap card — the card's
whole job is to give the user a reason to keep it on a desk or in a pocket. The interaction:
tap the card to start a lock → fold out the kickstand → stand the phone up. The card is the
thing you set the phone on, not a gimmick tap.

This spec covers the **standard (black anodized) card** and the three sellable **variants**.
A related but separate program — **Earned Cards** — reuses this same physical spec with
engraving changes only; see §6.

---

## 2. Physical spec (standard card)

| Spec | Value |
|---|---|
| Footprint | **85 × 54 mm** (standard credit-card footprint) |
| Thickness | **2–3 mm** |
| Material | Anodized aluminum (preferred) or stainless steel |
| Finish | Laser-engraved logo, anodized black (standard SKU) |
| Mechanism | Hinged / fold-out kickstand ("card stand" format), props phone at **~60°** |
| Hinge cycle rating | Request factory's rated open/close cycle count before committing — this is a wear part and needs a real spec, not an assumption |
| Edge features (optional, quote separately) | Bottle-opener notch on one edge; small ruler-marked edge |
| Corner treatment | Rounded/deburred — this rides in a pocket, no sharp edges |
| Weight | Request factory spec at final thickness/material; confirm it still feels premium, not flimsy |

**Kickstand mechanism note for the factory:** the fold-out mechanism is the single point of
mechanical failure on this product. Confirm with the factory:
- What hinge type they use (friction hinge, pivot rivet, living hinge in a second material, etc.)
- Rated cycle life before the hinge loosens or the stand won't hold angle
- Whether the hinge design changes per variant (Desk variant is heavier/non-portable — see §5)

---

## 3. CRITICAL: on-metal NFC requirement

**Metal blocks NFC.** This is not optional and must be raised with the factory on day one,
before any tooling or sampling begins — see `docs/spec.md` §25.2 and §27.

The NFC tag must use one of these two approaches. Confirm in writing which one the factory is
quoting:

1. **On-metal / ferrite-backed NFC inlay** (preferred — keeps the card solid metal).
   A ferrite (or equivalent shielding) layer sits between the metal card body and the NFC
   antenna/chip to prevent the metal from detuning or blocking the tag.
2. **Recessed non-metal window** — a cutout in the metal backed with resin, ceramic, or plastic,
   with a standard (non-on-metal) inlay mounted in the window.

**Do not let the factory substitute a standard adhesive NFC inlay directly onto/into bare metal
with no shielding or window.** It will not reliably read, or will have a read range too short to
be usable as a tap-to-lock gesture.

### Chip / tag spec
- Chip: **NTAG215** (or NTAG213/216 family) — matches the Tag Pack product (`docs/spec.md` §25.1,
  §27) for consistency and to keep the app's NFC read path uniform.
- Encoding: **NDEF URL record**, `zano://tag/<uuid>` scheme, same as Tag Pack — this keeps
  Shortcuts automations working (see §27 gotcha: background NFC reading needs an NDEF URL).
- Each unit needs a unique UID/UUID provisioned before or during assembly — confirm the
  factory's serialization/write process and whether they write tags or ship blank for us to write.

### Cost delta (budget explicitly, per unit, at quoted MOQ)
| Inlay type | Budget |
|---|---|
| Standard adhesive NFC inlay (non-metal product) | ~$0.10 |
| **On-metal / ferrite-backed inlay (this product)** | **~$0.30–0.60** |

Flag this delta explicitly in every quote request — a factory that quotes a metal card at
standard-inlay pricing has misunderstood the requirement and the read range will fail.

### Read-range testing is mandatory before production
See §7 — do not skip to a production PO on the strength of a datasheet. Read range must be
verified on the **exact metal, thickness, and inlay placement** being ordered, on a real iPhone.

---

## 4. Assembly / construction notes for the quote request

- Confirm inlay placement (which face, offset from hinge/edges) — must avoid the hinge
  mechanism and any metal reinforcement that would add a second layer of shielding.
- Confirm whether engraving (logo, and later serial/handle/date for Earned Cards — §6) is
  laser-engraved after anodizing (standard for legible, durable marks on anodized aluminum).
- Confirm packaging: card should arrive in retail-ready packaging suitable for unboxing-video
  use (`docs/spec.md` calls the Lock Card the "unboxing/UGC engine" — §25.0) — get a packaging
  quote alongside the unit quote.

---

## 5. Variants (quote each separately)

Per `docs/spec.md` §25.2:

| Variant | Description | Notes for factory |
|---|---|---|
| **Lock Card Desk** | Heavier puck/stand version for desk or nightstand. Non-portable — triggers focus or bedtime lock. | Different weight/material target than the pocket card; hinge or base may differ. Get a separate mechanical spec, not just a material swap. |
| **Lock Key** | Keychain/carabiner tag for the gym bag. Cheapest variant. | No fold-out kickstand — this is a small tag form factor, not the 85×54mm card. Confirm keyring attachment point strength and on-metal inlay still applies if metal-bodied. |
| **Lock Card MagSafe** | Magnet-backed version, sticks to mirror or fridge (feeds the Sunrise Alarm feature, `docs/spec.md` §5.10, §25.2). | **Magnet placement is a second interference risk alongside the metal body** — confirm with the factory that the magnet array does not further degrade NFC read range beyond the metal-only case. Test this specifically in §7, not just the standard card. |

Target retail range across the line (from §25.2): Lock Key **$2 COGS → ~$12 price**; standard
and other variants inside the COGS/price band in §6 below.

---

## 6. Earned Cards program (engraving requirements)

Per `docs/spec.md` §25.3 — this is not a separate product, it's the **same physical card spec**
with a different engraving package, awarded (not sold) to subscribers who hit retention
milestones. Build the engraving capability into the factory relationship from the first sample
run, even though initial production is the standard black card.

| Milestone | Card tier | Finish | Engraving |
|---|---|---|---|
| 30-day streak | Bronze | Bronze anodized/plated | Serial number |
| 100-day streak | Silver | Silver anodized/plated | Serial number |
| 365-day streak | Diamond | Diamond/premium finish | **Serial number + user's handle + date** |

Requirements to confirm with the factory:
- Laser engraving must support **variable data per unit** (serial number is unique per card;
  Diamond tier also engraves a unique handle + date) — this is a per-unit custom job, not a bulk
  run of identical cards. Confirm minimum order behavior for engrave-to-order / low-volume
  variable engraving (this may run in small batches outside the main MOQ, not a single 500–1,000
  unit run).
- Confirm turnaround time for a small-batch variable-engraving order separately from the
  standard-SKU production lead time in §8 — earned cards ship on a rolling basis as individual
  users hit milestones, not as one bulk drop.
- Rule from spec §21 (carried over here): these are status/cosmetic objects only, never sold —
  don't let packaging or store integration imply they can be purchased.

---

## 7. Sample-run + NFC-read-range test checklist

Per `docs/spec.md` §25.5. Run this before committing to a production PO. Do not skip.

### Sample run
- [ ] Order a **sample run of 3–5 units** per variant being considered (~$50–150 per sample
      order) before any production commitment.
- [ ] Confirm sample units use the **exact** metal, thickness, inlay type/placement, and (for
      MagSafe) magnet configuration intended for production — a sample on different stock
      invalidates the read-range test.

### NFC read-range test (on a real iPhone — not a simulator, not a generic NFC reader)
- [ ] Test tap-to-read reliability at normal "tap to phone" distance/angle, phone case on and off.
- [ ] Test read range/reliability specifically through a common phone case (silicone, MagSafe
      case) since users will tap with a case on.
- [ ] Test at the card's actual carry orientation (wallet, pocket, keychain for Lock Key) to catch
      real-world misalignment, not just a lab-perfect tap.
- [ ] For the **MagSafe variant**: test with the card mounted to its magnetic surface (mirror/
      fridge) and with a phone's own MagSafe magnets nearby, to catch magnet-on-magnet
      interference in addition to the metal-body issue.
- [ ] For the **Desk variant**: test with the phone resting in the actual stand position (this is
      the real-use tap geometry, not a flat tap).
- [ ] Record pass/fail per unit, per variant, and keep the failing units — send them back to the
      factory as reference if read range fails, rather than describing the problem verbally.
- [ ] Only proceed to a production PO after read range passes consistently across all sample
      units of a given variant.

### Mechanism check (fold-out kickstand)
- [ ] Open/close the hinge repeatedly (at minimum, to the factory's rated cycle count if
      available) and confirm it still holds the phone at a stable angle afterward.
- [ ] Confirm the stand holds a phone (with a typical case) at the ~60° angle on a real desk
      surface without sliding or tipping.

---

## 8. Cost & ordering targets

Per `docs/spec.md` §25.0 and §25.5:

| Item | Target |
|---|---|
| Target COGS (standard card, at MOQ) | **$3–6 / unit** |
| Target retail price | **$29–39** |
| MOQ, custom metal card | **500–1,000 units** |
| MOQ, tags alone (if sourced separately) | as low as 100–500 |
| Sample order cost | ~$50–150 for 3–5 units |
| Lead time — sampling | 2–4 weeks |
| Lead time — production | 3–5 weeks |
| Lead time — freight (air, first run) | 2–5 weeks |
| **Total, decision → doorstep** | **~10–12 weeks** — plan backward from any drop date |

Fulfillment: self-ship the first run (unboxing quality stays in our control per §25.5); move to a
3PL once volume makes self-fulfillment a bottleneck.

Compliance note (from §25.5): passive NFC tags are not FCC-regulated (no transmitter), but
confirm for any future active/Bluetooth hardware. Standard consumer product labeling and
small-parts/choking warnings apply to a metal card of this size.

---

## 9. Open items to resolve with the factory before PO

- [ ] Written confirmation of on-metal/ferrite inlay approach (§3) and the per-unit cost delta.
- [ ] Hinge mechanism spec and rated cycle life (§2).
- [ ] Variable-data engraving capability and small-batch turnaround for Earned Cards (§6).
- [ ] MagSafe magnet-vs-NFC interference test result (§7) before greenlighting that variant.
- [ ] Packaging quote for unboxing-grade retail packaging (§4).

---

*This sheet is derived from `docs/spec.md` §25.2, §25.3, §25.5 (and cross-referenced §25.0, §27,
§5.3, §5.10). If a factory conversation surfaces a spec change (e.g., a different inlay approach,
a different MOQ), update `docs/spec.md` first, then this sheet — spec.md is the source of truth.*
