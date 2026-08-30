# Boarding matrix: which stage a resume lands at

The stage is derived from `savepoint.md`'s last line plus the real artifacts on disk.
Classify from the last line alone, then verify only that line's artifact is real
(sentinel-aware). When the ledger is stale, rebuild it from disk and note it.

| savepoint last line | latest delivered | lands at | continue with |
|---|---|---|---|
| `What  {id}--{slug}.md` (born) | What | **Why** | the thinking conversation (`plastic-intent-speccing`) or direct work |
| `Why  started` (spec still sentinel) | What | **Why** | continue the conversation; rulings land as insights |
| `Why  spec.md created` | Why | **How** | the action files, `plan.md`, `checklist.md` |
| `How  started` / `How  plan.md created` | (How in progress) | **How** | finish `plan.md` and `checklist.md` |
| `How  checklist.md created` / `Exec  started` | How | **Exec** | do the work, check off the checklist |
| `Exec  outcome.md created` | Exec | **ready to complete** | the ending procedure (`plastic-intent-ending`) |
| `Done  delivered` / `Done  abandoned` | terminal | **report only** | immutable; ask what is next |

## Per-stage behaviour (what "continue" means)

- **Why**: continue the conversation, or run the work directly when the request is already
  clear; every ruling is recorded as it lands.
- **How**: write or finish the action files, `plan.md`, and `checklist.md`.
- **Exec**: verify what is delivered, then continue (or restart) the delivery or research.
  The first unchecked `checklist.md` item is the next step; the newest `## Insights` entry
  supplies the context.
- **ready to complete**: `outcome.md` is real; run the ending procedure.
- **Done**: terminal. Report the outcome, ask what is next. Never reopen; `INDEX.md` is
  authoritative.

## Notes

- A Plastic 1.x ledger may carry a `Tier  <letter>` line under the `Why  spec.md created` line
  (the intent tier was removed in 2.0, intent 304). It is inert: skip it when classifying.
- An `## Insights` entry marked `(autonomous)` means an auto team was delivering the intent;
  say so and offer to hand back to `plastic-auto`.
