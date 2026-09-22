# Plan: Separate maintenance from work (intent 197)

> **For agentic workers:** Use `plastic-intent-executing` to implement this plan. Tier L: one
> self-contained `actions/ACTION_N.md` per task below. Each action names the exact file,
> function, and discovery citation; re-deriving design from spec.md is not required.

**Tier:** L. 13 tasks, one action file each (`ACTION_1.md` .. `ACTION_13.md`).

**Goal:** Ship the WORK-vs-MAINTENANCE distinction as working tooling, not prose alone: a
generalized tool-enforced `revisions.md` receipt (project-links, rebuild-graph,
restore-intent-v1, the curator), a detect-only-lock + branch-and-merge-back maintenance
mechanism that never acquires a second lock, `project-links`'s two proof-case fixes
(single-intent scope, malformed-orphan reporting), `end-intent`'s `git add -A` -> scoped
commit, `doctor --fix-all` documented as a pure router, the corrected PLASTIC.md doctrine, and
the three live `graph_links_projection` repairs run through the new tooling.

## Where the code lives

All code changes land in the intent's own code worktree, already provisioned:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/197--separate-maintenance-from-work`
(branch `plastic/197--separate-maintenance-from-work`). Every action below is written and
committed there. **Branch-only, no merge, no release**: this delivery stops after the last
commit lands on that branch. Do not merge to main, do not tag, do not run `plastic-releasing`.
Intent 178 (store worktrees) is a hard dependency for full isolation (D16/D17) and merges
first, on the owner's own schedule; 197 merges after, both releasing together as one batch.
Record this explicitly in `outcome.md` at Done (see Task 13).

**Task 13's three proof-case repairs are the one exception to "all code changes land in the
worktree" above**: they mutate OTHER users' project stores under `~/.plastic`
(`projects/dealintell/store/...`, `store/26--ai-agents-resources`), never the plastic project's
own code. They run from the **worktree's own `scripts/maintenance-run`** (so the tool under
test is the one just built) but their effect lands in `~/.plastic`, a separate git repository
from the code worktree. See Task 13 and the Risk note below.

**Suite command** (confirmed from `.github/workflows/test.yml` and `AGENTS.md`):
```
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```
Never `ruby -Itest test/*_test.rb` (shell-expands the glob; only the first match runs).
**Baseline, measured today from the worktree**: 1557 runs, 5318 assertions, 0 failures, 0
errors, 0 skips. Every task ends with this suite green and the run/assertion count at or
above baseline (new tests only add, nothing here should remove coverage).

## Dependency-ordered tasks

| # | Task | Depends on | Files (see action for exact paths) |
|---|---|---|---|
| 1 | `project-links --intent <id>` single-intent scope | none | `scripts/project-links` |
| 2 | `project-links` reports a malformed/unresolvable Links line as a finding (still drops it) | none | `scripts/project-links` |
| 3 | New shared `RevisionsWriter` lib (append-only entry render + IO), generalized from `restore_intent_v1.rb`'s pattern | none | `scripts/lib/revisions_writer.rb` (new) |
| 4 | Wire `RevisionsWriter` into `project-links`: every applied change writes/appends a receipt in the same write, or the tool rolls back rather than leave an unrecorded change | 1, 2, 3 | `scripts/project-links` |
| 5 | Wire `RevisionsWriter` into `rebuild-graph`: same discipline | 3 | `scripts/rebuild-graph` |
| 6 | `restore-intent-v1`: prove (test-only) its existing writer already satisfies append-only `vN+1` | none | `test/restore_intent_v1_test.rb` |
| 7 | Store curator: tool-enforced (agent-enforced) receipt contract + detect-lock/branch/merge doctrine for maintenance outside its own delivery | none | `agents/plastic-intent-curator.md`, `skills/store-curating/SKILL.md` |
| 8 | New `MaintenanceGit` lib: clean-tree precheck, branch-from-main, scoped commit, merge-back, never `-A` | none | `scripts/lib/maintenance_git.rb` (new) |
| 9 | New `scripts/maintenance-run` CLI: wraps project-links/rebuild-graph/restore-intent-v1 with `Lock.fresh?` detect-and-defer (never acquire) + `MaintenanceGit` isolation | 1, 2, 4, 5, 8 | `scripts/maintenance-run` (new) |
| 10 | `end-intent`'s `store_commit`: `git add -A` -> scoped commit of the completing intent's own paths | none | `scripts/end-intent` |
| 11 | `doctor --fix-all` documented as a router; doctor gains no write path | 9 | `skills/doctor/SKILL.md`, `scripts/doctor.rb` (fix_hint text only) |
| 12 | PLASTIC.md doctrine rewrite (WORK vs MAINTENANCE, stale 112/two-lock correction, target-state rule, detect-only lock, branch-and-merge, no `add -A` anywhere) | 1-11 (must describe what actually shipped) | `PLASTIC.md`, `PLASTIC-reference.md` |
| 13 | The three live proof-case repairs, run through `maintenance-run`; final suite + em-dash guard + outcome.md sequencing note | 9, 12 | `~/.plastic` store (global `26`, `dealintell/3b`, `dealintell/15`); `outcome.md` |

**Why this order:** 1-2 are independent, low-risk changes to one already-well-tested file
(`project-links`) and land first so 4 has stable ground to wire onto. 3 is pure infrastructure
with no caller yet, so it can be written and unit-tested in isolation before anything depends
on it. 4-5 wire 3 into the two tools that today write no receipt at all (the discovery's
Inconsistency #2 - the exact gap 197 exists to close). 6 only adds test coverage (no code
risk) so it can land any time after the others' pattern is set, independent of them. 7 is prose
plus doctrine for the one non-code writer (the curator agent), independent of the code tasks.
8 is infrastructure (branch/merge) with no caller yet, same shape as 3. 9 is the first task
that composes everything built so far (1, 2, 4, 5, 8) into one operable CLI, so it must come
after all of them. 10 is independent of 1-9 (a different script, `end-intent`, not touched by
any tool above) but is placed here because it is this intent's own safety-floor deliverable and
has no dependency on the maintenance mechanism. 11 documents 9's existence, so it follows it.
12 is placed second-to-last because it must describe the SHIPPED mechanism accurately (D18 is
explicit that stale doctrine is worse than no doctrine); writing it before the code exists risks
exactly the 112 failure mode this intent is fixing. 13 runs last, deliberately: it is the proof
case, and per D20/the spec's own rejected-alternative table, repairing the three violations
"ahead of the new maintenance path... contradicts this intent's own condition" - if 13 cannot
be done through `maintenance-run`, the intent has disproven itself and must stop, not fall back
to a hand edit.

## Acceptance criteria coverage

All 18 spec.md acceptance criteria map to a task; see `checklist.md` for the exact mapping
(every AC is covered by at least one task; several tasks jointly cover one AC).

## Risks and open items for Exec to carry

- **Task 13 runs against a live, shared git repo (`~/.plastic`) that is not this branch.**
  `git -C ~/.plastic status --porcelain` shows pre-existing unrelated dirty files today
  (`.cache/update-check.json`, `manifest.json`, an audit dry-run file) - exactly the hazard
  `MaintenanceGit`'s clean-tree precheck (Task 8) exists to refuse loudly rather than silently
  sweep up. Before running Task 13, the operator must either commit/stash those unrelated
  changes or Task 13 will abort at the precheck (correct, intended behavior, not a bug to route
  around).
- **Task 13 is a store mutation, not a code-worktree mutation.** It has no merge-to-main step
  of its own to skip (there is nothing to merge; `maintenance-run`'s own branch-and-merge-back
  happens entirely inside `~/.plastic`, already lands on `~/.plastic`'s own `main`). This does
  NOT violate the "branch-only, no merge" constraint above, which governs the plastic **code**
  branch only. Flagging this explicitly per the dispatch brief: the three repairs are store
  writes to `global` and `dealintell`, never to the plastic project's own code or its branch.
- **No acceptance criterion requires a merge to ship.** All 18 ACs are verifiable on the
  intent's own branch plus the store-side proof-case commits described above; none names
  "merged to main" as its own success condition (the one AC naming 178's merge is a sequencing
  record, satisfied by an `outcome.md` note, not by 197 merging).
- `rebuild-graph` is store-wide with no single-id scope (unlike `project-links` after Task 1).
  Task 9's wrapper handles this by dry-running first, checking `Lock.fresh?` across every id the
  dry run would touch, and refusing the WHOLE run if any is fresh, rather than attempting a
  partial per-id skip. Simpler and matches D10's "wait" semantics exactly.
