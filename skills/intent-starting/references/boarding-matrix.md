# Boarding matrix — which station Start drops you at

The station is derived from `savepoint.md`'s last line plus the real artifacts on disk.
Classify from the last line alone, then verify ONLY that line's artifact is real
(sentinel-aware). On drift, rebuild the ledger from disk and note it.

| savepoint last line | latest delivered | boards at | continue with |
|---|---|---|---|
| `What  {id}--{slug}.md` (born) | What | **What / Why** | What work (106-expanded), then brainstorm → `spec.md` |
| `Why  started` (spec still sentinel) | What | **Why** | continue brainstorming → `spec.md` |
| `Why  spec.md created` | Why | **How** | `plan.md` + `actions/` + `checklist.md` |
| `How  started` / `How  plan.md created` | (How in progress) | **How** | finish `plan.md` → `checklist.md` |
| `How  checklist.md created` / `Exec  started` | How | **Exec** | implement, tick the checklist |
| `Exec  outcome.md created` | Exec | **ready to complete** | exit at Done |
| `Done  delivered` / `Done  abandoned` | terminal | **report only** | immutable; ask what is next |

## Per-station behaviour (what "continue" means)

- **What** → do what What requires (to be expanded in 106), then brainstorm → `spec.md`.
- **Why** → continue brainstorming; deliver `spec.md`.
- **How** → continue `plan.md` + `actions/` + `checklist.md`.
- **Exec** → verify what has been delivered, then continue (or restart) the delivery /
  research. The first unchecked `checklist.md` item is the next step; the newest `## Insights`
  entry supplies human-readable context.
- **ready to complete** → `outcome.md` is real; run the ending procedure (~93).
- **Done** → terminal. Report the outcome, ask what is next. Never reopen; INDEX is
  authoritative.

## Notes

- The mode (auto / guided) is asked exactly ONCE, whatever station Start lands at. It is never
  re-asked at a later station. The lock is taken FIRST regardless of station (terminal intents
  excepted: they get no lock and no resume).
- An `## Insights` entry marked `(autonomous)` means the intent was being delivered
  autonomously; in guided mode, surface that and offer to hand back to `plastic-auto`.
