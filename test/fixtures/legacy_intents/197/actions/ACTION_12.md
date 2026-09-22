# ACTION_12 - PLASTIC.md doctrine rewrite: WORK vs MAINTENANCE

Depends on ACTIONS_1-11 (this action must describe the mechanism as SHIPPED, per D18's own
lesson: writing doctrine before the code exists is exactly how intent 112's stale prose
survived for years). Covers 6 of spec.md's 18 ACs at once (the PLASTIC.md-doctrine ACs): the
plainly-stated WORK vs MAINTENANCE section, the two-lock/112 correction, the
maintenance-needs-an-intent exception, the target-state rule, the detect-only-lock statement,
and the branch-and-merge-plus-no-`add -A` statement.

File: `PLASTIC.md` (inside the worktree). All quoted "current" text below is verbatim from a
fresh read of the file today; line numbers may drift slightly by the time this action runs if
an earlier action's own diff shifts them - match by TEXT CONTENT (`old_string` in the Edit
tool), not by line number.

## 12a. Replace the two-lock doctrine paragraph

Current:
```
Two locks share this schema (the two-lock doctrine): `delivery.lock` (exclusive, one owner
plus delegates) and the future `maintenance.lock` (short TTL, structural move-and-record
only). They are mutually exclusive in either direction; maintenance is allowed at any
lifecycle stage provided no delivery lock is held. Intent 108 ships the delivery lock and
the mutual-exclusion seam; the maintenance lock implementation follows intent 93 in a
chained intent.
```

Target:
```
There is exactly one lock in Plastic: `delivery.lock` (exclusive, one owner plus delegates),
shipped by intent 108. An earlier two-lock doctrine proposed a second `maintenance.lock`
(short TTL, structural move-and-record only); intent 112 built it in full and was then
abandoned before merge on a design pivot, so nothing from it ever shipped (`lock.rb`'s
`TYPES` seam is the only trace left). Intent 197 rejects the second lock outright rather than
reviving it: a lock held by a maintenance session could be mistaken by a resuming session
for an active delivery. Maintenance instead DETECTS `delivery.lock`'s freshness
(`Lock.fresh?`) and defers when fresh; it never acquires any lock of its own and leaves none
behind. See "WORK vs MAINTENANCE" below for the full doctrine.
```

## 12b. Replace the Maintenance row in the "Intent delivery, station by station" table

Current row:
```
| Maintenance (any stage) | `revisions.md` move-and-record entries | future `maintenance.lock` (short TTL), mutually exclusive with `delivery.lock` in either direction; 108 ships the schema seam only, the implementation follows intent 93 in a chained intent | acquisition refuses while the other lock type is fresh; a terminal intent with no lock held is read-only | dated, rule-tagged `revisions.md` entry; savepoint untouched |
```

Target row:
```
| Maintenance (Future, Terminal, or Active-with-a-stale-or-no-lock) | `revisions.md` move-and-record entries | detects (never acquires) `delivery.lock`; defers and reports while the target's lock is FRESH (`Lock.fresh?`); a stale or absent lock is not-active, maintenance proceeds | none enforced by any gate; the maintenance tool or skill itself checks `Lock.fresh?` (see WORK vs MAINTENANCE below) | append-only, rule-tagged `revisions.md` entry written in the same operation as the change, or the change is refused; lands via a fresh branch off store main merged back as one closed op, never `git add -A` |
```

## 12c. Replace "Terminal immutability" through the "Restore-to-v1" paragraph with a new "WORK vs MAINTENANCE" section

Current (both paragraphs, verbatim, immediately after "### What "intent done" means (intent
93)"'s block and before "Fail-safe lock doctrine"):
```
Terminal immutability (the contract intent 112 enforces): a terminal directory is writable
ONLY while a lock is held. The delivery lock covers the completing session's End tail up to
`Lock.release`; the maintenance lock covers sanctioned structural move-and-record edits
after. Terminal with no lock held is frozen. There are only two locks in the system,
delivery and maintenance (108 D11). This governs WRITES only: reads of a terminal intent are
always allowed and unbounded (curator reindex, dashboards, and future intents that reference
its id or chain), so a done intent stays fully readable forever. Intent 93 states this rule;
intent 112 builds the gate that enforces it.

Restore-to-v1 (the owner rule that a completed intent is immutable: a late ruling goes to a
new `--parent` branch intent, and the completed intent is restored to v1) is performed ONLY by
`scripts/restore-intent-v1`, run under the maintenance lock. Its prose (the intent narrative,
checklist.md, outcome.md, spec.md, plan.md) is immutable and reverts to v1; its frontmatter
graph (`sources`/`chain`) is metadata about OTHER intents, not content of this one, and is
APPEND-ONLY: it is preserved as the union of the v1 snapshot and the current snapshot, never
subtracted. A hand-run whole-file `git checkout`/revert of a completed intent is FORBIDDEN,
because it cannot distinguish prose from graph metadata and silently destroys backlinks written
after v1 (proven on intent 124: a legitimately accrued chain edge was destroyed by a hand-run
restore and went undetected for a week). This governs the restore mechanism only; it does not
loosen terminal immutability itself.
```

Target (replaces BOTH paragraphs above with one new section; keep everything before and after
byte-identical):
```
### WORK vs MAINTENANCE (intent 197)

Plastic separates two different things an earlier doctrine blurred under one word,
"immutable." WORK is the delivered CONTENT an intent produced: the code and project files a
delivery changed, the research it recorded, the outcome it wrote. Once the intent is terminal
(Completed or Abandoned), that content is immutable - the only way to change it is another
intent that continues or reverts it. Editing a Done intent's own artifacts so it looks like it
delivered something different, or that parts are missing, is forbidden (the book analogy:
never rewrite the text on the pages of an old, valuable book).

MAINTENANCE is everything else: structure, the sources/chain graph, a section that does not
belong in the file, formatting, and any store-wide operational change (a new Plastic version
adding or removing a frontmatter field across every intent). Maintenance is not immutable and
needs no owner gate to run, on the one condition below (recording is universal). The
decidable test is CONTENT vs METADATA, not "meaning vs structure": a graph edit is structure
even when it is also, in a loose sense, about lineage, because it does not change what the
intent delivered. Precedent: plastic intent 124's own `revisions.md` v1 dropped a dead chain
edge to a non-existent `124b` (`[rule: broken-chain]`), and v2 added a missing required
reciprocity edge to `131` (`[rule: misplaced-content]`), both ordinary maintenance, not
owner-gated exceptions. Allowed maintenance: (a) a frontmatter chain/sources edge that points
to a non-existent or wrong intent, or a missing required edge; (b) an extra non-convention
section in the intent file, removed and moved into `revisions.md`; (c) a store-wide
operational change from a new Plastic version, applied to every intent; (d) any other
structural or operational tidy. Forbidden: anything that alters what the work delivered.

The residual guard on every graph edit: it must move TOWARD ground truth (drop a dangling or
false edge, add a reciprocity-forced or documented-real one) and must never invent a
relationship - "might be related" is never a valid `[rule:]` reason. This is already implied
by the mandatory `[rule: tag]` on every `revisions.md` entry; no additional per-edit owner
gate is needed for an ordinary graph fix of this kind.

Maintenance normally needs no intent and no roadmap at all; it runs through the maintenance
tools and skills and records itself. The one exception: a batch touching more than about 5
different intents at once must stay rare, and is always an owner decision - the agent asks
first and shows the diff before proceeding. This exception governs rare cross-intent sweeps;
it does not apply to an ordinary single-intent graph repair.

Maintenance target-state eligibility, by the intent's own lifecycle state: a Future intent,
yes; a Terminal (Completed or Abandoned) intent, yes; an Active intent mid-delivery, WAIT. The
wait is keyed on whether the target currently holds a FRESH `delivery.lock` (`Lock.fresh?`),
never on INDEX `## Active` membership - `end-intent` releases the lock only after the INDEX
move and its commit tail finish, so keying on Active membership would miss that tail window
and let maintenance race a live completion. A STALE lock is not maintenance's problem to
resolve; it is treated as not-active, and maintenance proceeds rather than waiting
indefinitely behind a dead session.

There is exactly one lock in the system (see the two-lock correction above): `delivery.lock`,
meaning an active agent is delivering that intent. Maintenance DETECTS this lock and NEVER
ACQUIRES it, even transiently, because a maintenance-held lock could be mistaken by a resuming
or continuation session for an active delivery. Maintenance leaves no lock behind: there is
nothing to clean up afterward, and no ambiguity about who, if anyone, holds the one lock.
`bridge.rb:1195`'s `lock_gate_decision` already allows any write once an intent is not in
INDEX `## Active` - there is no enforced freeze gate in the codebase today, and there never
was one that shipped (see the corrected history below).

Stranding and clobbering are avoided by construction, not by a second lock: a maintenance
action creates a fresh branch from the CURRENT state of store main, applies only its own
scoped changes, and merges that branch back to main as part of the SAME closed operation.
Nothing strands on an unmerged branch; two concurrent maintenance runs reconcile as ordinary
merge conflicts on main, never silent loss. This is lighter than intent 178's full per-session
delivery worktrees (178 stays about the agent write paths for delivery); maintenance only
needs branch-from-main plus scoped merge-back (`scripts/lib/maintenance_git.rb`,
`scripts/maintenance-run`).

No commit anywhere, store or project repo, uses `git add -A`; every maintenance and delivery
commit stages only the paths it actually changed (`scripts/end-intent`'s `store_commit`,
`scripts/maintenance-run`).

The one condition on every maintenance action, with no exception, is that it is recorded.
Every maintenance action, whether run by a tool or made by hand, must leave an append-only
`revisions.md` entry on its target intent (`## Revision vN`, a `Why ... [rule: tag]` line, a
`Prior location`, and the change itself). If the file already exists, a new run appends
`vN+1`; it never overwrites an earlier entry (precedent: intent 124's `revisions.md` v3
corrects v2 by appending a correction entry and explicitly leaving v2 in place). This is
tool-enforced, not prose alone: `scripts/project-links`, `scripts/rebuild-graph`, and
`scripts/restore-intent-v1` each write this receipt in the SAME write as the structural
change, or refuse to proceed without one (`scripts/lib/revisions_writer.rb`); the intent
curator (`agents/plastic-intent-curator.md`) holds itself to the identical rule by hand.

Doctor stays a detector: core and full checks, every installed agent, both global and project
stores. It gains no write path of its own. The "Fix all" prompt
(`skills/doctor/SKILL.md`) is a ROUTER: for each fixable finding it dispatches to the tool
that already owns that class of repair (`project-links`, `rebuild-graph`,
`restore-intent-v1`, or the curator, via `scripts/maintenance-run` where applicable), and
those tools perform the mutation and write the `revisions.md` receipt - never doctor itself.

Corrected history (D18): an earlier version of this section described a terminal-immutability
gate "intent 112 enforces" and a two-lock model. Intent 112 built that gate in full and was
then ABANDONED before merge on a design pivot; nothing from it ever shipped. `bridge.rb:1195`
confirms no such gate runs today: a write to a terminal intent is allowed unconditionally once
the intent leaves INDEX `## Active`. The deadlock that stopped intents 189, 192, and 195 from
repairing three live `graph_links_projection` violations was self-imposed discipline (agents
and the owner both treating undocumented doctrine as a real gate), not a technical one. This
section is the corrected doctrine; intent 112's own history stays in INDEX as an abandoned,
superseded design.

Restore-to-v1 (the owner rule that a completed intent is immutable: a late ruling goes to a
new `--parent` branch intent, and the completed intent is restored to v1) is performed ONLY by
`scripts/restore-intent-v1`. Its prose (the intent narrative, `checklist.md`, `outcome.md`,
`spec.md`, `plan.md`) is immutable and reverts to v1; its frontmatter graph
(`sources`/`chain`) is metadata about OTHER intents, not content of this one, and is
APPEND-ONLY: preserved as the union of the v1 snapshot and the current snapshot, never
subtracted. It writes its own `revisions.md` receipt in the same run. A hand-run whole-file
`git checkout`/revert of a completed intent is FORBIDDEN, because it cannot distinguish prose
from graph metadata and silently destroys backlinks written after v1 (proven on intent 124: a
legitimately accrued chain edge was destroyed by a hand-run restore and went undetected for a
week).
```

## 12d. Fix the "Scope split" paragraph's stale intent-112 credit

Current (last paragraph of the file's locking section, `PLASTIC.md`, near the end):
```
Scope split. Intent 93 ships doctrine plus the low-risk reconciliation that needs no new
lock: the canonical done-marker and three-signal reconciliation, the mandatory `outcome.md`
plus `disposition` header at both terminals, the End tail with the reindex moved last, the
`done_signals` doctor check (three-signal agreement plus stalled-completion detection), and
the lock-bounded post-done window with its keep-guard test. Intent 111 owns the lock
liveness surface, the lock-issue message, orchestrator auto-repair, and the fail-open
behavior itself. Intent 112 owns the maintenance lock and the immutability gate (it inherits
fail-open from 111). Intent 4a1b1 owns deep agent stuck-detection and is not superseded.
```

Target (only the one sentence about 112 changes; everything else byte-identical):
```
Scope split. Intent 93 ships doctrine plus the low-risk reconciliation that needs no new
lock: the canonical done-marker and three-signal reconciliation, the mandatory `outcome.md`
plus `disposition` header at both terminals, the End tail with the reindex moved last, the
`done_signals` doctor check (three-signal agreement plus stalled-completion detection), and
the lock-bounded post-done window with its keep-guard test. Intent 111 owns the lock
liveness surface, the lock-issue message, orchestrator auto-repair, and the fail-open
behavior itself. Intent 112 attempted a maintenance lock and an immutability gate; it was
abandoned before merge and superseded by intent 197's WORK vs MAINTENANCE doctrine
(detect-only lock, branch-and-merge, tool-enforced `revisions.md`). Intent 4a1b1 owns deep
agent stuck-detection and is not superseded.
```

## 12e. `PLASTIC-reference.md` - register the two new tool-authored rule tags

Current (`PLASTIC-reference.md`'s "Violation tags (starter set...)" list):
```
Violation tags (starter set, free-text tags allowed):
- `unsanctioned-section`: a top-level section the sanctioned-section rule now rejects
- `phantom-section`: a section referenced but not present or not sanctioned
- `stray-file`: a file that does not belong in the intent directory
- `dangling-ref`: a link or reference to something that no longer exists
- `broken-chain`: a chain frontmatter edge to an intent that no longer exists
- `broken-source`: a sources frontmatter edge to an intent that no longer exists
- `misplaced-content`: content that belongs in a different artifact or section
```

Target (appends two entries; nothing existing removed or reordered):
```
Violation tags (starter set, free-text tags allowed):
- `unsanctioned-section`: a top-level section the sanctioned-section rule now rejects
- `phantom-section`: a section referenced but not present or not sanctioned
- `stray-file`: a file that does not belong in the intent directory
- `dangling-ref`: a link or reference to something that no longer exists
- `broken-chain`: a chain frontmatter edge to an intent that no longer exists
- `broken-source`: a sources frontmatter edge to an intent that no longer exists
- `misplaced-content`: content that belongs in a different artifact or section
- `links-projection`: a tool-authored `## Links` regeneration (project-links; intent 197)
- `graph-rebuild`: a tool-authored sources/chain frontmatter rebuild (rebuild-graph; intent 197)
```

## Verify

No Ruby test exercises `PLASTIC.md`/`PLASTIC-reference.md` prose directly. Verify by:
1. `grep -n "maintenance.lock\|intent 112 enforces\|intent 112 builds the gate" PLASTIC.md`
   returns nothing (the stale claims are gone).
2. `grep -n "WORK vs MAINTENANCE" PLASTIC.md` finds the new section.
3. Full Ruby suite still green (no code depends on this file's prose; this is a documentation
   task with zero code-execution risk, but the suite is run anyway per plan.md's every-task
   discipline).
4. No em-dash introduced anywhere in this action's new text (the target blocks above already
   use plain hyphens throughout; confirm with `grep -n $'-' PLASTIC.md
   PLASTIC-reference.md` after the edit, expecting only the store's own EM_DASH-in-INDEX
   convention untouched elsewhere, not any new occurrence in the edited passages).
