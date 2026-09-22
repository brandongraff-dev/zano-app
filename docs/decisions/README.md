# Decisions

`docs/spec.md` says "when you change a decision, change it here first" — meaning edit the spec
directly. Use this folder only when a change is big enough to need its own rationale trail (e.g.
reversing a §12 tech-stack choice, changing the data model after §13 is "frozen," dropping/adding a
goal type's verification tier). For everything else, just edit `docs/spec.md` and note the change
in the relevant session doc.

One file per decision: `NNNN-short-title.md` — context, decision, why, what it changes downstream.
Keep `docs/spec.md` as the up-to-date result; this folder is the paper trail for *why* it changed.
