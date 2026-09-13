Tier: L
# Spec: Separate maintenance from work (work is immutable, maintenance is not)

## Problem

Plastic's own doctrine blurs two different things under one word, "immutable," and the blur has
a real cost. PLASTIC.md (lines around 624-631) describes a Completed or Abandoned intent as
frozen the moment its lock is released, and credits intent 112 as the gate that enforces this.
Verified: intent 112 was abandoned before merge, nothing from it ever shipped, and the code that
actually runs today (`bridge.rb:1195`) already lets any write through once an intent is not in
INDEX's `## Active` list. There is no enforced freeze in the codebase, only doctrine that claims
one, and today's honest deadlock was self-imposed discipline, not a technical gate.

Because agents and the owner both treated that doctrine as if it were a real gate, a genuine
structural defect in a Completed intent could not get repaired. Three `graph_links_projection`
violations (global `26`, dealintell `3b`, dealintell `15`) survived two intents built specifically
to fix them: 189 and 192 both closed with the repair PROPOSED, never RUN, for the sole reason that
the target intents were Completed.

A second, sharper problem sits on top of the first: one whole class of defect is invisible by
design. A hand-authored `## Links` line with a malformed slug (single dash, for example dealintell
3b's `3d-payments-subscription-gating` against the real directory
`3d--payments-subscription-gating`) resolves to nothing. It is caught by neither 192's write-time
Links gate (which only checks lines it writes) nor 189's orphan-preserve rule (which only
preserves an unbacked line that DOES resolve). A broken link is therefore silently droppable the
next time anyone reprojects Links, and nobody is ever told. `project-links` also has no way to
regenerate a single intent's `## Links` section on its own, so even a willing agent cannot repair
just one target through the tool without touching every other intent in the store.

Underneath both problems is a missing enforcement mechanism: even once the distinction is stated,
nothing today guarantees a maintenance change is ever recorded. `revisions.md` is a documented
convention (intent 107) that is invisible to every validator, gate, and doctor check; only one
tool, `restore_intent_v1.rb`, actually writes one. A rule that lives only in prose is not a rule
agents will reliably follow under time pressure.

Without one plain, working distinction between what must never change (a Done intent's delivered
content) and what is allowed to be repaired (its structure, graph, and operational metadata),
enforced by the tools themselves rather than by honor system, the store keeps producing known,
verified defects that no one is able to fix safely.

## Goals

- PLASTIC.md states the WORK vs MAINTENANCE distinction plainly, as a named deliverable: WORK is
  the delivered CONTENT an intent produced (code and project files changed, research recorded,
  outcome prose), immutable once the intent is terminal, changeable only through another intent
  that continues or reverts it. MAINTENANCE is structure, the sources/chain graph, and
  operational uniformity across the store (repairing a wrong or dangling chain/sources edge,
  adding a missing required edge, moving a non-convention section into `revisions.md`, applying a
  store-wide operational change), not immutable, allowed on any target intent subject to the
  condition below. The decidable test is content vs metadata, not "meaning vs structure."
- PLASTIC.md's stale prose (lines around 624-631, a two-lock model plus a terminal-immutability
  gate credited to intent 112) is corrected to state reality: exactly one lock (delivery), no
  enforced freeze gate, and the `revisions.md` receipt is the whole maintenance contract.
- PLASTIC.md states when maintenance needs its own intent: normally never; only as a rare
  exception for a batch touching more than about 5 different intents at once, and only after the
  owner is asked first and shown the diff.
- PLASTIC.md states the maintenance target-state rule: Future intents = yes; Terminal intents =
  yes; an Active intent mid-delivery = wait, keyed on whether it holds a FRESH delivery lock
  (`Lock.fresh?`), never on INDEX `## Active` membership (which would miss the commit-tail window
  after `end-intent` moves the INDEX entry but before it releases the lock). A stale lock is
  treated as not-active; maintenance proceeds.
- No second "maintenance lock" is built. The existing delivery lock stays the only lock.
  Maintenance DETECTS a fresh delivery lock and defers; it never ACQUIRES any lock and leaves none
  behind.
- Maintenance avoids stranding and clobbering by construction: it branches from the current state
  of store main, applies only its own scoped changes, and merges back to main as part of the same
  closed operation, never leaving a change stranded on an unmerged branch.
- Every maintenance action (tool-run or manual) writes an append-only `revisions.md` entry on its
  target intent (`## Revision vN`, a `[rule: tag]` reason, prior location, the change diff) as a
  named, tool-enforced deliverable: `project-links`, `rebuild-graph`, `restore-intent-v1`, and the
  store curator write this receipt themselves, in the same write as the change, or refuse to
  proceed. `restore_intent_v1.rb` already does this for its own frontmatter move-and-record;
  this intent generalizes that one pattern to the other tools.
- No commit anywhere (store or project repo) uses `git add -A`; every maintenance and delivery
  commit stages only the paths it actually changed.
- Doctor stays a read-only detector (core and full checks, every installed agent, both global and
  project stores) and gains no write path of its own. `doctor --fix-all` is documented and behaves
  as a router: it dispatches each detected, fixable issue to the maintenance tool that already
  owns that class of repair.
- `project-links` accepts a single-intent scope (for example `--intent <id>`) so it can regenerate
  exactly one intent's `## Links` section without touching any other intent in the store.
- `project-links` reports an unresolvable `## Links` line as a malformed-orphan candidate instead
  of silently dropping it, the same way it already reports a resolvable-but-unbacked orphan.
- `end-intent`'s `store_commit` step changes from `git add -A` at the store root to a scoped
  commit of only the completing intent's own paths, the minimal safety floor that makes 197 safe
  to ship before intent 178 (store worktrees) lands.
- The three live `graph_links_projection` violations (global 26, dealintell 3b, dealintell 15)
  are repaired through the new maintenance path as the proof case, each leaving a `revisions.md`
  receipt on the repaired intent, never by hand.
- Sequencing is explicit: nothing in this intent ships ahead of the mechanism it depends on. 197
  is delivered on a branch; intent 178 (store worktrees) is delivered and merged first; then 197
  merges; both release together as one batch.

## Non-Goals

- The generic handling of the 44 `signals_complete` terminal gaps (40 missing `outcome.md`, 3
  missing the savepoint Done echo, 1 placeholder) is out of scope. Sibling intent 211 owns it;
  197 leaves the 44 gaps untouched.
- Removing or replacing the shipped `scripts/lib/legacy_bookend_amnesty.rb` file is out of scope.
  Intent 211 owns it.
- The founding rule that no personal or user-specific store data ships in the npm package is out
  of scope as a general packaging guard. Intent 211 owns it.
- A second "maintenance lock" type is not built at all, not deferred: it is rejected outright, on
  the ground that a maintenance-held lock could be mistaken by a resuming session for an active
  delivery lock.
- Doctor does not gain a write, `--fix`, or `--apply` mutate mode of any kind. `--fix-all` stays a
  router; the tools it dispatches to do the writing.
- Intent 178's own worktree wiring is a hard dependency of this intent's safe sequencing, but
  building or wiring 178 itself is not part of 197's delivery.
- General backfilling of a Done intent's content is out of scope. The only exception on record is
  a Done intent missing a file Plastic needs to operate on it at all (an operational gap), and
  none of the three proof-case repairs in this intent are content backfills; they are graph
  repairs.

## Approach

PLASTIC.md gets one clear, plainly stated distinction. WORK is what an intent's delivery actually
changed: the code and project files it touched, the research it recorded, the outcome it wrote.
Once the intent is terminal, that content is immutable. The only way to change it is another
intent that continues or reverts it; editing a Done intent's own artifacts so it looks like it
delivered something different, or that parts are missing, is forbidden (stated once, using the
book analogy: never rewrite the text on the pages of an old, valuable book). MAINTENANCE is
everything else that is structure rather than content: the sources/chain graph, a section that
does not belong in the file, formatting, and any store-wide operational change (such as a new
Plastic version adding or removing a frontmatter field across every intent). Maintenance is not
immutable and needs no owner gate to run, provided it always moves the graph toward ground truth
(dropping a dangling or false edge, adding a reciprocity-forced or documented-real one) and never
invents a relationship; "might be related" is never a valid reason. The decidable test is content
vs metadata, not "meaning vs structure": a graph edit is structure even when it is also, in a
loose sense, about lineage, because it does not change what the intent delivered. Precedent for
this already exists in plastic intent 124's own `revisions.md`: v1 dropped a dead chain edge to a
non-existent `124b` (`[rule: broken-chain]`), and v2 added a missing required reciprocity edge to
`131`, both ordinary maintenance, not owner-gated exceptions.

Maintenance normally needs no intent and no roadmap at all; it runs through the maintenance tools
and skills and records itself. The one exception is a batch that touches many different intents
at once (rule of thumb: more than about 5), which must stay rare. Any such batch is an owner
decision: the agent always asks first and always shows the diff, what changes and what the
difference is, before proceeding. This exception governs rare cross-intent sweeps; it does not
apply to an ordinary single-intent graph repair such as the three proof-case violations below,
which are merged into this intent's own delivery rather than gated per-repair.

Maintenance is eligible on a target intent by state: a Future intent, yes; a Terminal (Completed
or Abandoned) intent, yes; an Active intent that is mid-delivery, wait. The wait is keyed on
whether the target currently holds a FRESH delivery lock (`Lock.fresh?`), never on INDEX
`## Active` membership, because `end-intent` releases the lock only after the INDEX move and its
commit tail finish, so keying on Active membership would miss that tail window and let
maintenance race a live completion. A stale lock is not maintenance's problem to resolve; it is
treated as not-active and maintenance proceeds. There is exactly one lock in the system, the
delivery lock, meaning "an active agent is delivering this intent." Maintenance DETECTS this lock
and never ACQUIRES it, because a maintenance-held lock could be mistaken by a resuming or
continuation session for an active delivery. Maintenance leaves no lock behind, so there is
nothing to clean up afterward and no ambiguity about who, if anyone, holds the one lock.

Maintenance avoids stranding and clobbering by construction rather than by a second locking layer:
it creates a fresh branch from the current state of store main, applies only its own scoped
changes (never `git add -A`, only the paths it actually touched, in both the store and the
project repo), and merges that branch back to main as part of the same closed operation. Because
merge-back is part of the operation, nothing strands on an orphaned branch, and two concurrent
maintenance runs reconcile as ordinary merge conflicts on main rather than silent loss. This is
lighter than intent 178's full per-session delivery worktrees (178 stays about the agent write
paths for delivery); maintenance only needs branch-from-main plus scoped merge-back.

The one condition on every maintenance action, with no exception, is that it is recorded. Every
maintenance action, whether run by a script or made by hand, must leave an append-only
`revisions.md` entry on its target intent: a `## Revision vN` header, a `Why ... [rule: tag]`
line, the prior location, and the change itself. If the file already exists, a new run appends
`vN+1`; it never overwrites an earlier entry (precedent: intent 124's `revisions.md` v3 corrects
v2 by appending a correction entry and explicitly leaving v2 in place). Guaranteeing this in
practice means the recording instruction lives inside the tool that does the work, not in prose
a human might skip: `project-links`, `rebuild-graph`, `restore-intent-v1`, and the store curator
each write their own `revisions.md` receipt in the same write as the change, or refuse to proceed
without one. `restore_intent_v1.rb` already renders exactly this entry shape for its own
frontmatter move-and-record (its `render_revision_entry` helper); this intent generalizes that one
proven pattern into the other mutating tools rather than inventing a new format.

Doctor's role does not change shape, only its job description gets sharper and its two blind
spots get closed. Doctor stays a detector: core and full checks, every installed agent, both
global and project stores. It gains no write path. `--fix-all` is documented as an explicit
router: for each fixable finding it dispatches to the tool that actually owns that repair
(`project-links` for Links-graph drift, `rebuild-graph` for graph rebuilds, `restore-intent-v1`
for frontmatter move-and-record, the store curator for structural section moves), and those tools
perform the mutation and write the `revisions.md` receipt, never doctor itself.

`project-links` gains the two fixes this intent's own proof case needs, brought back into 197
rather than left with sibling 211: a single-intent scope flag (for example `--intent <id>`) so a
maintenance run can regenerate exactly one intent's `## Links` section without touching any other
intent in the store, and a change to its orphan-handling so that an unresolvable `## Links` line
(a slug that resolves to no real directory) is reported as a malformed-orphan candidate instead of
being silently dropped. Today `project-links` only preserves a line that resolves but has no
frontmatter backing; a line that resolves to nothing is invisible to that rule and to 192's
write-time gate alike, so it disappears from the file the next time anyone reprojects Links, with
no notice to anyone. Reporting it, the same way resolvable orphans are already reported, closes
that blind spot without changing what gets written.

`end-intent`'s `store_commit` step changes from `git add -A` at the store root to a scoped commit
of only the completing intent's own changed paths. This is the minimal floor that makes 197 safe
to ship before intent 178 (store worktrees) lands: today a concurrent delivery's `add -A` could
sweep up a maintenance session's uncommitted change-plus-receipt on the same shared checkout, and
scoping the commit turns that failure mode from a silent clobber into, at worst, a loud merge
conflict.

The three live violations are the proof case for the whole design, repaired only once the
maintenance path (the tool-side `revisions.md` writers, the `project-links` scope flag, and the
branch-and-merge-back mechanism) exists, never by hand and never ahead of it:

| Intent | What is wrong | Repair | Maintenance class |
|---|---|---|---|
| global 26 | Frontmatter already has the real chain edge to `ai-agents-resources:1`; the `## Links` section still has a stale comment claiming no edges | Reproject Links to add the one real line. Adds only, nothing removed | Ordinary graph maintenance, moves toward ground truth |
| dealintell 3b | Three single-dash lines to 3c, 3d, 3e resolve nowhere; 3c/3d/3e are siblings of 3b (all `sources: ["3"]`), so a chain edge from 3b to any of them would be false, and the real seams are already in 3b's own Context prose | Reproject Links, keeping the real `3` line and dropping the three malformed sibling lines | Ordinary graph maintenance, drops a false edge |
| dealintell 15 | Its `## Links` line to 3a is real but unbacked; frontmatter is missing the edge | Add `"15"` to 3a's `chain`, then reproject both 15's and 3a's Links sections | Ordinary graph maintenance, adds a documented-real, reciprocity-forced edge |

None of the three repairs is an owner-gated exception; each is ordinary maintenance under the
rules above, run through the new tooling, with a `revisions.md` receipt on its target as the
whole contract. Nothing ships until the mechanism exists: 197 stays on a branch while intent 178
(store worktrees) is delivered and merged first, then 197 merges, and both deliver and release
together as one batch. All work ideated in the course of designing 197 is delivered inside 197
rather than fragmented elsewhere; sibling intent 211 has been informed of exactly what 197 covers
and keeps its own distinct scope (the 44 `signals_complete` gaps generically, removing the shipped
`legacy_bookend_amnesty.rb`, and the no-personal-data-ships packaging rule).

The standard, boring option is the one taken throughout: reuse the already-documented
`revisions.md` convention and the single existing delivery lock, generalize the one tool that
already writes a receipt correctly (`restore_intent_v1.rb`) rather than invent a new audit
mechanism, and use an ordinary git branch-and-merge for isolation rather than a new locking
primitive.

## Alternatives Considered

| Alternative | Not chosen because |
|---|---|
| Two-lock model: delivery lock plus a maintenance lock, even a short-TTL or transiently-acquired one | A lock held by a maintenance session could be mistaken by a resuming session for an active delivery lock. Matches parked intent 122's own conclusion to keep exactly one lock, and intent 112 already built and abandoned a two-lock design |
| Hard terminal-freeze gate enforcing zero writes to Completed or Abandoned intents | Never actually shipped in code; `bridge.rb:1195` already allows all terminal writes. The deadlock that stopped 189, 192, and 195 was self-imposed discipline, not a technical gate, so keeping the doctrine only misleads agents into refusing legitimate repairs |
| The advisor's initial framing: "meaning vs structure" is not decidable, so frontmatter sources/chain edges always need an owner gate | Withdrawn on review. Content vs metadata is decidable and precedent-backed (intent 124): a graph edit that moves toward ground truth and never invents a relationship is ordinary maintenance, not an owner-gated exception |
| Maintenance transiently acquires the delivery lock for its short write window, for real mutual exclusion | Rejected: a maintenance-held lock, even briefly, could be mistaken by a resuming or continuation session for an active delivery. Maintenance stays detect-only; residual maintenance-vs-maintenance concurrency is handled by branch-and-merge, not by locking |
| Heavy per-session worktrees for maintenance, matching intent 178's delivery-worktree design | Maintenance does not need that much machinery. A fresh branch off current store main, scoped changes, and a merge-back as part of the same operation avoids stranding by construction and is lighter than 178's full agent-write-path worktrees |
| Frozen id-allowlist amnesty for old-intent gaps, the 170a precedent, applied again to the 44 `signals_complete` gaps | Does not scale past one user's store; the existing amnesty file already ships one owner's roughly 70 personal ids inside the npm package, the exact anti-pattern being rejected. The 44-gap question is spun into sibling intent 211 instead |
| Doctor gains a `--fix` or `--apply` mutate mode | Reverses the design already settled at intents 107 and 122: doctor stays read-only detection that informs a human or router first |
| Repair the three live violations by hand now, ahead of the new maintenance path | Contradicts this intent's own condition: every fix must be recorded in `revisions.md` and run through a maintenance tool, so the repair waits for and goes through that path rather than preceding it. If the only available path to a repair is a hand edit, the intent has disproven itself |
| A dedicated new malformed-ref scan as doctor's main fix for the silent-drop bug | Mostly redundant: the existing `graph_links_projection` check already flags all three live violations. The real uncovered bug is `project-links` silently dropping an unresolvable line; the fix is reporting it as an orphan candidate, in the same place the tool already reports resolvable orphans |

## Decisions

- D1: Maintenance normally needs no intent and no roadmap. It runs through the maintenance tools
  and skills and records itself in `revisions.md`.
- D2: Exception to D1: maintenance needs an intent and a roadmap only when it is a batch of many
  different things at once (rule of thumb: more than about 5). This must stay rare.
- D3: Data-backfill stance: stay away from backfilling Done intents. Only Future and Active
  intents undergo backfills as normal work.
- D4: Exception to D3: a Done intent missing a key file that Plastic needs to operate on it (so
  the intent cannot be read or processed at all) is fixed via maintenance plus `revisions.md`.
  Cosmetic or delivery-claim gaps in a Done intent are not operational and do not qualify.
- D5: Any backfill batch is an owner decision. The agent always asks first and always shows the
  diff, what changes and what the difference is, and proceeds only after the owner allows it.
- D6: No maintenance lock is needed. `revisions.md` captures the change diff itself, every
  removal, addition, and modification. The delivery lock stays the only lock, and the
  `revisions.md` receipt is the whole maintenance contract. This matches parked intent 122's own
  conclusion; 122 is merged into 197 and marked Abandoned as superseded, so 197 carries its
  design forward rather than starting a new one.
- D7: Doctor stays a detector (core and full, all installed agents, global and project stores). It
  does not gain a write mode. `doctor --fix-all` is a router that dispatches each detected issue
  to the appropriate maintenance tool or skill, and those tools do the writing and record
  `revisions.md`.
- D8 (the precise immutability line, supersedes an earlier, rejected framing): work done by using
  an intent's artifacts to change code, project files, or record research is the DELIVERED
  CONTENT, and it is immutable once the intent is terminal. Changing a Done intent's artifacts so
  it looks like it performed or delivered something else, or that parts are missing, is forbidden
  (book analogy: never rewrite the text on the pages of an old, valuable book). Sources/chain
  edges and structure are metadata and relationships, not delivery meaning: fixing a wrong,
  dangling, or missing graph edge is legitimate maintenance with a `revisions.md` record (you may
  reorder dropped pages or fix the cover, but you must record the revision). Allowed maintenance
  is: (a) a frontmatter chain/sources edge that points to a non-existent or wrong intent, or a
  missing required edge; (b) an extra non-convention section in the intent file, removed and moved
  into `revisions.md`; (c) a store-wide operational change from a new Plastic version, applied to
  every intent; (d) any other structural or operational tidy. Forbidden is anything that alters
  what the work delivered. Precedent: plastic intent 124's `revisions.md` v1 removed a chain edge
  to a non-existent `124b` (`[rule: broken-chain]`) and v2 added a missing required reciprocity
  edge to `131`, exactly this class of fix.
- D9: The residual guard on every graph edit, already implied by the mandatory `[rule: tag]` on
  every `revisions.md` entry: a graph edit must move TOWARD ground truth (drop a dangling or false
  edge, add a reciprocity-forced or documented-real one) and must never invent a relationship.
  "Might be related" is not a valid `[rule:]` reason. No per-edit owner approval gate is needed
  for an ordinary graph fix of this kind.
- D10: Maintenance target-state eligibility: Future intents, yes. Terminal intents, yes. An Active
  intent mid-delivery, wait, keyed on whether it currently holds a FRESH delivery lock
  (`Lock.fresh?`), not on INDEX `## Active` membership (which would miss the commit-tail window
  between the INDEX move and the lock's release at the end of `end-intent`). A stale lock is
  treated as not-active; maintenance proceeds rather than deferring indefinitely.
- D11: There is exactly one lock, the delivery lock, meaning an active agent is delivering the
  intent. Maintenance DETECTS this lock and never ACQUIRES it, even transiently, because a
  maintenance-held lock could be mistaken by a resuming or continuation session for an active
  delivery. Maintenance leaves no lock behind.
- D12: Stranding and clobbering are avoided by construction, not by a second lock: maintenance
  creates a fresh branch from the current state of store main, applies only its own scoped
  changes, and merges that branch back to main as part of the same closed operation. Concurrent
  maintenance runs reconcile as ordinary merge conflicts, never silent loss. This is lighter than
  intent 178's full per-session delivery worktrees, which stay scoped to delivery write paths.
- D13: No commit anywhere, in the store or the project repo, uses `git add -A`. Every commit
  stages only the paths the session actually changed. A maintenance action's change and its
  `revisions.md` receipt are written and committed together as one scoped commit, the atomic unit
  of the maintenance contract.
- D14: Recording is universal and tool-enforced: every maintenance action, script-run or manual,
  must leave an append-only `revisions.md` entry on its target (`## Revision vN`, a
  `[rule: tag]` reason, prior location, the change). If the file exists, append `vN+1`; never
  overwrite (precedent: intent 124's `revisions.md` v3 appends a correction to v2, leaving v2 in
  place). The recording instruction lives inside the mutating tools themselves: `project-links`,
  `rebuild-graph`, `restore-intent-v1`, and the store curator write this receipt in the same write
  as the change, or refuse. `restore_intent_v1.rb` already does this for frontmatter
  move-and-record; this intent generalizes that one pattern to the other tools.
- D15: No fragmentation: all work designed in the course of this intent's Why stage is delivered
  inside 197, not split into other intents. The `project-links` single-intent scope flag and the
  report-don't-drop fix for unresolvable `## Links` lines, briefly parked in sibling 211, come
  back into 197. 211 is informed of exactly what 197 covers and keeps its own distinct scope: the
  44 `signals_complete` gaps generically, removing the shipped `legacy_bookend_amnesty.rb`, and
  the no-personal-data-ships packaging rule.
- D16: Sequencing: ship nothing until the underlying mechanism is done. 197 stays on a branch;
  intent 178 (store worktrees) is delivered and merged first; then 197 merges; then both deliver
  and release together as one batch.
- D17: The end-intent safety floor: `end-intent`'s `store_commit` step changes from `git add -A`
  at the store root to a scoped commit of only the completing intent's own paths. This is the
  minimal change that makes 197 safe to ship before intent 178 lands; without it, a concurrent
  delivery's `add -A` could still sweep up a maintenance session's change on the shared checkout.
- D18: PLASTIC.md's stale prose (lines around 624-631) crediting intent 112 with an enforced
  terminal-immutability gate, and describing a two-lock model, is corrected as part of this
  intent, since 112 was abandoned and never shipped, and `bridge.rb:1195` confirms no such gate
  runs today.
- D19: The frozen-allowlist approach to old-intent gaps is rejected; it does not scale past one
  user's store. The shipped `scripts/lib/legacy_bookend_amnesty.rb` already hardcodes the owner's
  personal intent ids inside the npm package, the exact anti-pattern being rejected. Plastic must
  instead define bare-minimum generic rules that apply to every user, not id lists. The 44
  `signals_complete` gaps are left alone for now; the whole old-intent-maintenance question,
  including replacing the shipped amnesty file, is spun into sibling intent 211.
- D20: The three live violations (global 26, dealintell 3b, dealintell 15) are the proof case.
  They are repaired through the new maintenance path only, each leaving a `revisions.md` receipt
  on the repaired intent; none of the three is an owner-gated exception, each is ordinary
  maintenance under D8/D9.

## Acceptance Criteria

- [ ] PLASTIC.md contains a plainly stated WORK vs MAINTENANCE section defining WORK as the
  delivered content (code, project files, research, outcome), immutable except via a continuing
  or reverting intent, and MAINTENANCE as structure, graph, and operational uniformity, allowed on
  any target intent subject only to the `revisions.md` condition below.
- [ ] PLASTIC.md's lines describing a two-lock model and crediting intent 112 with an enforced
  terminal-immutability gate no longer make that claim; the corrected text states exactly one
  lock (delivery) and the `revisions.md` contract, citing `bridge.rb:1195` as the current
  behavior.
- [ ] PLASTIC.md documents the maintenance-needs-an-intent exception: normally never; only for a
  batch of more than about 5 items at once; must be rare; requires an owner ask-first and
  diff-shown-first step.
- [ ] PLASTIC.md documents the maintenance target-state rule: Future = yes, Terminal = yes,
  Active-and-fresh-lock = wait, Active-with-stale-lock = proceed, keyed on `Lock.fresh?`, not on
  INDEX `## Active` membership.
- [ ] PLASTIC.md documents that maintenance is detect-only on the delivery lock: it never
  acquires any lock, and leaves none behind.
- [ ] PLASTIC.md documents the branch-from-main-and-merge-back mechanism maintenance uses for
  isolation, and states that no commit anywhere (store or project repo) uses `git add -A`.
- [ ] `project-links`, `rebuild-graph`, and `restore-intent-v1` each write (or already write) an
  append-only `revisions.md` entry on their target intent in the same write as their change, or
  refuse to proceed without one; a test exists proving each tool actually writes the entry on a
  fixture change and appends `vN+1` rather than overwriting when the file already exists.
- [ ] `project-links` accepts a single-intent scope flag (for example `--intent <id>`) that
  regenerates exactly one intent's `## Links` section and leaves every other intent's file
  untouched, with a test proving no other intent's file changes.
- [ ] `project-links` reports an unresolvable `## Links` line as a malformed-orphan candidate
  instead of silently dropping it, with a test built on a fixture unresolvable line proving the
  tool produces a finding rather than an empty result.
- [ ] `end-intent`'s `store_commit` step stages only the completing intent's own changed paths,
  never `git add -A` at the store root, with a test proving an unrelated modified file elsewhere
  in the store is not included in the commit.
- [ ] Doctor's `--fix-all` behavior is documented as dispatching each fixable finding to the named
  maintenance tool (`project-links`, `rebuild-graph`, `restore-intent-v1`, or the curator); doctor
  itself gains no `--apply` or `--fix` mutation code path.
- [ ] Global intent 26's `## Links` section is regenerated, through `project-links`, to include
  the `ai-agents-resources:1` edge, and a `revisions.md` entry exists on 26 recording the change
  with a `[rule:]` tag.
- [ ] Dealintell 3b's `## Links` section no longer contains the three single-dash malformed lines
  (to 3c, 3d, 3e), regenerated through `project-links`; its real `3` line remains; a
  `revisions.md` entry exists on 3b recording the removal with a `[rule:]` tag.
- [ ] Dealintell 3a's frontmatter `chain` includes `"15"`, both 3a's and 15's `## Links` sections
  are reprojected through `project-links` to reflect the edge, and a `revisions.md` entry exists
  recording the addition with a `[rule:]` tag.
- [ ] Each of the three repairs above was made by branching from current store main, applying only
  that repair's scoped change, and merging back to main as part of the same operation, never by a
  manual `Edit`/`Write` to the target intent's files and never left stranded on an unmerged branch.
- [ ] A doctor run performed after all three repairs reports zero `graph_links_projection`
  warnings for ids 26, 3b, and 15.
- [ ] Intent 178 (store worktrees) is Completed and merged to main before 197's own branch merges;
  197's merge commit or outcome.md records this ordering.
- [ ] The 44 `signals_complete` gaps, `legacy_bookend_amnesty.rb`, and the general
  no-personal-data-ships packaging rule are untouched by this intent's delivery; intent 211 remains
  their owner.

## Open Questions

None. Every question raised during Why has a resolving Decision:
- Whether a "meaning vs structure" gate on graph edits is needed: resolved by D8/D9 (content vs
  metadata is decidable; no per-edit owner gate for ordinary graph fixes).
- Whether intent 122 should be merged into or left parallel to 197: resolved by D6 (merged,
  122 marked Abandoned as superseded).
- Whether PLASTIC.md's stale intent-112 prose should be corrected as part of this intent: resolved
  by D18.
- Whether maintenance needs to acquire a lock for real mutual exclusion: resolved by D11
  (detect-only, never acquire).
- Whether maintenance needs heavy per-session worktrees: resolved by D12 (branch-and-merge-back
  is sufficient).
- Whether the wait-on-delivery rule keys on INDEX Active membership or lock freshness: resolved by
  D10 (keys on `Lock.fresh?`).
- Whether 197 is safe to ship before intent 178 lands: resolved by D16/D17 (yes, once the
  end-intent scoped-commit floor, D17, ships; 178 still merges first as the stronger guarantee).
- Whether the project-links `--intent` scope and report-don't-drop fixes belong in 197 or sibling
  211: resolved by D15 (both come back into 197; 211 keeps its own distinct scope).

One item remains genuinely unresolved and is carried forward rather than settled here: the
`mihradesign/1--functional-qa-roadmap/revisions.md` schema drift (missing the `## Revision vN`
header, no `Why [rule: tag]` line, no `Prior location`) is a real, live instance of a maintenance
record that does not match the documented shape. No owner ruling on record states whether this
intent's delivery fixes that one file as a side effect of shipping the new tool-side writers, or
whether it is left for a later, separate maintenance pass. The planner should treat it as
optional, not required, absent a ruling.
