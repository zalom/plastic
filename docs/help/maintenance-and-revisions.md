# Maintenance and Revisions

This chapter holds WORK vs MAINTENANCE, the revisions.md move-and-record contract, the violation-tag catalog, and the context-economy measurement buckets.

## WORK vs MAINTENANCE

Plastic separates two different things an earlier doctrine blurred under one word,
"immutable." WORK is the delivered CONTENT an intent produced: the code and project files a
delivery changed, the research it recorded, the outcome it wrote. Once the intent is terminal
(Completed or Abandoned), that content is immutable - the only way to change it is another
intent that continues or reverts it. Editing a terminal intent's own artifacts so it looks like it
delivered something different, or that parts are missing, is forbidden (the book analogy:
never rewrite the text on the pages of an old, valuable book).

MAINTENANCE is everything else: structure, the sources/chain graph, a section that does not
belong in the file, formatting, and any store-wide operational change (a new Plastic version
adding or removing a frontmatter field across every intent). Maintenance is not immutable and
needs no owner gate to run, on the one condition below (recording is universal). The
decidable test is CONTENT vs METADATA, not "meaning vs structure": a graph edit is structure
even when it is also, in a loose sense, about lineage, because it does not change what the
intent delivered. Allowed maintenance: (a) a frontmatter chain/sources edge that points
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

There is exactly one lock in the system (see `plastic help locks-and-worktrees`):
`delivery.lock`,
meaning an active agent is delivering that intent. Maintenance DETECTS this lock and NEVER
ACQUIRES it, even transiently, because a maintenance-held lock could be mistaken by a resuming
or continuation session for an active delivery. Maintenance leaves no lock behind: there is
nothing to clean up afterward, and no ambiguity about who, if anyone, holds the one lock.
No code freezes a terminal intent: nothing blocks a write anywhere.

Stranding and clobbering are avoided by construction, not by a second lock: a maintenance
action creates a fresh branch from the CURRENT state of store main, applies only its own
scoped changes, and merges that branch back to main as part of the SAME closed operation.
Nothing strands on an unmerged branch; two concurrent maintenance runs reconcile as ordinary
merge conflicts on main, never silent loss. Maintenance only
needs branch-from-main plus scoped merge-back (`scripts/lib/maintenance_git.rb`,
`scripts/maintenance-run`).

No commit anywhere, store or project repo, uses `git add -A`; every maintenance and delivery
commit stages only the paths it actually changed (`scripts/end-intent`'s `store_commit`,
`scripts/maintenance-run`).

The one condition on every maintenance action that STRUCTURALLY EDITS AN INTENT'S OWN FILES is
that it is recorded. (One narrow carve-out exists for a tool that edits no intent directory at
all - see `register-exclusions` below.) Every such maintenance action, whether run by a tool or
made by hand, must leave an append-only `revisions.md` entry on its target intent (`## Revision
vN`, a `Why ... [rule: tag]` line, a `Prior location`, and the change itself). If the file
already exists, a new run appends
`vN+1`; it never overwrites an earlier entry. This is
tool-enforced, not prose alone: `scripts/project-links`, `scripts/rebuild-graph`, and
`scripts/restore-intent-v1` each write this receipt in the SAME write as the structural
change, or refuse to proceed without one (`scripts/lib/revisions_writer.rb`); a hand-applied
relocation holds itself to the identical rule.

`plastic doctor` stays a detector. It checks the installation, the machine database, each
registered project's store and its three databases, and the hooks and instruction files of the
harness it runs in. It reads files and opens the databases read-only, and it has no write path
of its own. Each finding names its repair: a command that owns that class of repair, such as
`plastic next`, `plastic project new SLUG PATH` or `plastic install --claude --reinstall`, or a
line to add to a file. Those commands make the change, never the doctor. A harness gets its
checks from its own module beside the shared ones, so a second harness adds a module and
changes no other. Claude Code and Codex have modules. The Codex module
checks its record in `~/.agents/plastic/VERSION`, the current kernel hook commands
and launchers in `~/.codex/hooks.json`, and its AGENTS.md line. Trust is unverified;
review `/hooks` in Codex. This reminder does not fail the file checks.

Restore-to-v1 (the owner rule that a completed intent is immutable: a late ruling goes to a
new `--parent` branch intent, and the completed intent is restored to v1) is performed ONLY by
`scripts/restore-intent-v1`. Its prose (the intent narrative, `checklist.md`, `outcome.md`,
`spec.md`, `plan.md`) is immutable and reverts to v1; its frontmatter graph
(`sources`/`chain`) is metadata about OTHER intents, not content of this one, and is
APPEND-ONLY: preserved as the union of the v1 snapshot and the current snapshot, never
subtracted. It writes its own `revisions.md` receipt in the same run. A hand-run whole-file
`git checkout`/revert of a completed intent is FORBIDDEN, because it cannot distinguish prose
from graph metadata and silently destroys backlinks written after v1.

Fail-safe lock doctrine: the lock system never traps a
session or burns credits. When a check cannot verify lock integrity it fails open, degrading
to advisory (warn) rather than refusing. Repair is orchestrator-driven: on a lock-issue
signal the orchestrator inspects the lock with `plastic intent lock status ID`, and an expired
lock is taken over by the next `plastic auto ID`.

`revisions.md` is an optional, append-only structural-maintenance audit trail. It is not a
lifecycle deliverable and is never scaffolded at intent birth. Its mere existence signals that
the intent underwent structural (not conceptual) change. Structural maintenance is move-and-record:
it removes a misplaced section, file, or ref from its artifact and preserves that content in full
inside `revisions.md` (newest entry at the bottom, one entry per relocated item), so no record is
lost and the delivered meaning is never altered. Changing what an intent delivered is a new intent,
not a revision.

## Structural maintenance and revisions.md

When a delivered intent accumulates structural junk (an unsanctioned section, a stray file, a
frontmatter edge to an intent that no longer exists), a relocation moves it into
`revisions.md` instead of reopening the work. Each entry is a versioned, dated header
(`## Revision vN - YYYY-MM-DD-HH:MM`) plus `Why` (one sentence naming the broken rule, ending
with `[rule: <tag>]`), `Prior location`, and either `Content held` (the verbatim removed
content) or, for a frontmatter edit, a one-line `Change` (before and after). A stray file has
its full content embedded and the original is deleted.

Violation tags (starter set, free-text tags allowed):
- `unsanctioned-section`: a top-level section the sanctioned-section rule now rejects
- `phantom-section`: a section referenced but not present or not sanctioned
- `stray-file`: a file that does not belong in the intent directory
- `dangling-ref`: a link or reference to something that no longer exists
- `broken-chain`: a chain frontmatter edge to an intent that no longer exists
- `broken-source`: a sources frontmatter edge to an intent that no longer exists
- `misplaced-content`: content that belongs in a different artifact or section
- `links-projection`: a tool-authored `## Links` regeneration (project-links)
- `graph-rebuild`: a tool-authored sources/chain frontmatter rebuild (rebuild-graph)

This is a starter set; free-text tags are allowed. `RuleCatalog::REVISION_RULES`
(`scripts/lib/rule_catalog.rb`) is the canonical, currently-in-use vocabulary,
measured from live store data rather than hand-curated, and `test/rule_catalog_test.rb` pins
every `[rule:]` literal hardcoded under `scripts/` as a registered member - so an unregistered
tag is caught before it ships, without `RevisionsWriter.append!` itself ever refusing to write
one (a receipt writer that refuses on an unrecognized tag would fail harder than the bug it is
meant to catch).

## register-exclusions: a maintenance tool that writes no revisions.md entry

`scripts/maintenance-run --tool register-exclusions [--rule <name>] [--store <key>] [--apply]`
is the one narrow exception to the "every maintenance action is recorded in
`revisions.md`" rule above. It populates each store's `doctor-exclusions` file (the per-store
record of knowingly-exempt `(intent_id, rule)` pairs `doctor`'s `savepoint_operational` check
honors) by computing violations through
`Doctor#done_signal_findings_for_dir` directly, the same function `check_done_signals` itself
calls, so the registry can never disagree with the checker about what counts as a violation.

The carve-out: this tool modifies no intent directory at all. It writes exactly one
store-level table per store (`doctor-exclusions`, sibling to `INDEX.md`), never an intent's
own files, so the receipt rule above - which covers tools that structurally edit an intent's
own files - does not apply to it. Writing a `revisions.md` receipt anyway would mean editing
every touched Completed intent directory, which the standing rule that completed intents are
immutable forbids outright. The receipt is instead the scoped git commit
(`MaintenanceGit.run_scoped`) plus the exclusion file itself, where every line is its own
durable, diffable record - not a missing safeguard, a deliberate substitution for a receipt
shape that would otherwise require an illegal write.

`--prune` reverses the same tool's direction under the identical carve-out: instead
of adding newly-violating ids, it removes rows that suppress nothing this run (the intent's gap
got repaired, the id was mistyped, or the intent directory is gone), computed via the same
`DoctorExclusions.dead_rows` predicate doctor itself reports from, so the reporter and the
remover can never disagree about what a dead row is. Same dry-run-by-default, same `--apply`
gate, same comment-preserving writer, same one scoped commit, same no-`revisions.md`-entry rule -
this direction still modifies no intent directory, only the store-level table. It holds back two
kinds of row before writing even when they read as dead: an id whose intent dir carries a fresh
delivery lock (the lock skip would otherwise leave it out of the walk entirely and misclassify
it), and an id whose intent has not reached a terminal state yet (`savepoint_operational` only
fires on a terminal intent, so the row has nothing to suppress *yet*). Both are named in the
output as kept, never silently dropped, and a rule left with zero ids after pruning is removed
from the file rather than written as a bare `rule_name` line the loader would reject.

Like every other tool behind `maintenance-run`, it dry-runs by default (the owner-approval
gate), unions with any existing hand-edited file content so a manually added id is never
dropped, and skips (never aborts on) any intent dir holding a fresh delivery lock.

## Context-economy measurement buckets

Three buckets measure what fills the context window.

- (a) hook prose tokens: the narration the lifecycle hooks emit into context.
- (b) main-loop store-read tokens: tokens the main agent spends reading or grepping the store
  in the transcript.
- (c) authored-section sizes: sizes of authored artifacts (INDEX entries and the like).
