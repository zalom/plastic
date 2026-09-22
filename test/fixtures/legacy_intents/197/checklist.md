# Checklist: Separate maintenance from work (intent 197)

Tier L. 13 actions, one per task in `plan.md`. Each box below is one action's completion
(code + tests green + its own AC(s) satisfied). The AC map shows every spec.md acceptance
criterion is covered by at least one action; several actions jointly cover one AC.

## In Progress
- [x] ACTION_1 - project-links: `--intent <id>` (+ `--store <key>` disambiguation) single-intent scope
- [x] ACTION_2 - project-links: report malformed/unresolvable Links lines instead of silent drop
- [x] ACTION_3 - new lib: `scripts/lib/revisions_writer.rb` (shared append-only writer)
- [x] ACTION_4 - wire RevisionsWriter into project-links (receipt-before-write, refuse on failure)
- [x] ACTION_5 - wire RevisionsWriter into rebuild-graph (same discipline)
- [x] ACTION_6 - restore-intent-v1: test coverage proving append-only `vN+1` (fix only if a real gap surfaces)
- [x] ACTION_7 - curator: tool-enforced receipt contract + detect-lock/branch-merge doctrine
- [x] ACTION_8 - new lib: `scripts/lib/maintenance_git.rb` (clean-tree, branch, scoped commit, merge-back)
- [x] ACTION_9 - new CLI: `scripts/maintenance-run` (detect-only lock + MaintenanceGit wrapper)
- [x] ACTION_10 - end-intent: `store_commit` scoped commit, never `git add -A`
- [x] ACTION_11 - `doctor --fix-all` documented as router; doctor gains no write path
- [x] ACTION_12 - PLASTIC.md doctrine rewrite (WORK vs MAINTENANCE, 112/two-lock correction, etc.)
- [x] ACTION_13 - the three live proof-case repairs through `maintenance-run`; final suite + em-dash guard + branch-only confirmation

## Acceptance criteria coverage (spec.md, 18 total)

| # | Acceptance criterion (abridged) | Covered by |
|---|---|---|
| 1 | PLASTIC.md states WORK vs MAINTENANCE plainly | ACTION_12 |
| 2 | PLASTIC.md corrects the two-lock / intent-112-enforces claim, cites `bridge.rb:1195` | ACTION_12 |
| 3 | PLASTIC.md documents the maintenance-needs-an-intent exception (rare, >~5, ask+diff) | ACTION_12 |
| 4 | PLASTIC.md documents the target-state rule (Future/Terminal yes, Active-fresh-lock wait, stale proceeds, keyed on `Lock.fresh?`) | ACTION_12 |
| 5 | PLASTIC.md documents maintenance is detect-only on the lock (never acquires, leaves none behind) | ACTION_12 |
| 6 | PLASTIC.md documents branch-from-main-and-merge-back + no `git add -A` anywhere | ACTION_12 (doctrine) + ACTION_8/ACTION_9 (mechanism) + ACTION_10 (end-intent's own no-`-A`) |
| 7 | project-links, rebuild-graph, restore-intent-v1 each write/already-write an append-only receipt in the same write or refuse; test proves `vN+1` append | ACTION_3 (shared writer) + ACTION_4 (project-links) + ACTION_5 (rebuild-graph) + ACTION_6 (restore-intent-v1 test) |
| 8 | project-links accepts `--intent <id>` scope, regenerates only that one intent, test proves no other file changes | ACTION_1 |
| 9 | project-links reports an unresolvable Links line as a malformed-orphan candidate instead of silently dropping it, with a fixture test | ACTION_2 |
| 10 | end-intent's `store_commit` stages only the completing intent's own paths, never `git add -A`, test proves an unrelated file is excluded | ACTION_10 |
| 11 | Doctor's `--fix-all` documented as dispatching to the named tools; doctor gains no `--apply`/`--fix` code path | ACTION_11 |
| 12 | Global 26's Links regenerated to include the real edge; revisions.md entry with `[rule:]` | ACTION_13 (13a) |
| 13 | Dealintell 3b's Links loses the 3 malformed lines, keeps the real `3` line; revisions.md entry | ACTION_13 (13b) |
| 14 | Dealintell 3a's chain includes `15`; both 3a's and 15's Links reprojected; revisions.md entry | ACTION_13 (13c) |
| 15 | Each of the three repairs done via branch-from-main + scoped change + merge-back, never a manual Edit/Write, never stranded | ACTION_13 (13a-13c, via `maintenance-run`/curator recipe) |
| 16 | A doctor run after all three repairs reports zero `graph_links_projection` warnings for 26, 3b, 15 | ACTION_13 (13d) |
| 17 | Intent 178 Completed and merged before 197's own branch merges; recorded in outcome.md or the merge commit | plan.md's branch-only constraint + ACTION_13 (13f, sequencing note prepared for the ending stage) |
| 18 | The 44 `signals_complete` gaps, `legacy_bookend_amnesty.rb`, and the packaging rule stay untouched (intent 211's scope) | ACTION_13 (13e.4, verified untouched) |

## Suite-green gate

- [x] Full suite green after every action (`ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'`), at or above the measured baseline: 1557 runs, 5318 assertions, 0 failures, 0 errors, 0 skips.
- [x] No em-dash or en-dash introduced in any added line across the whole diff (checked in ACTION_13's final pass, but worth re-checking after every action that touches prose).
- [x] Branch-only confirmed at the end: `plastic/197--separate-maintenance-from-work` has every new commit; the code repo's `main` is untouched by this intent; no merge, no tag, no `plastic-releasing` run.

## Completed
(move items here as each action lands, per the executor's own convention)

## Session Log
| Date | Items Completed | Notes |
|------|-----------------|-------|
| 2026-07-16 | How stage: plan.md, actions/ACTION_1.md..ACTION_13.md, checklist.md | Planner pass (Tier L, 13 actions, one per task). Baseline suite measured from the worktree before any code change: 1557 runs, 5318 assertions, 0 failures/errors/skips. Load-bearing correctness finding during planning: ids 26 and 15 both collide across real stores (global/mihradesign/plastic and dealintell/mihradesign/plastic respectively) - ACTION_1 and ACTION_9 both design explicit `--store <key>` disambiguation with a loud abort on ambiguity, mirroring restore-intent-v1's own established precedent, rather than silently resolving to the first match. |
| 2026-07-17 | Exec: actions 7-13 delivered (Waves A/B/C); 3 live repairs applied via maintenance-run | Suite 1594/5497 green; em-dash clean; branch-only (main untouched); doctor graph_links_projection PASS on 26/3b/15. On branch plastic/197, NOT merged. |
