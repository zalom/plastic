# Context Management (Save, then resume-flow debugging)

## Save Point
Triggered by PreCompact hook or manually:
1. Find active intent(s) from `~/.plastic/INDEX.md`
2. Update active intent's `checklist.md` (check off completed items)
3. Update active intent's `savepoint.md` (in-progress, next steps, blockers, discoveries)
4. Add observations to `## Insights`
5. Update INDEX.md
6. Commit: `cd ~/.plastic && git add . && git commit -m "chore: savepoint - [intent name]"`
7. Notify user to `/clear`

## Debugging the resume flow

When a resume looks wrong (the announced stage does not match what is on disk, or the next
step looks stale):

1. Read `savepoint.md`'s last line directly; that line alone is the source of truth for stage
   (see `SKILL.md`'s `## Conditional Ledger-Resume` for the full state table).
2. Confirm the artifact that line implies (`plan.md`, `checklist.md`, `outcome.md`, ...) is
   present and non-empty on disk.
3. If the two disagree, the ledger has drifted: rebuild it rather than hand-editing:
   `ruby -r ~/.plastic/scripts/lib/savepoint -e 'Savepoint.rebuild_savepoint("<intent_dir>")'`
4. Re-read the rebuilt last line and re-derive the next step from `checklist.md`'s first
   unchecked item.

The general "land on the board / priority order / stale future intents" flow now lives in
`plastic-project-continuing`; this file no longer duplicates it.
