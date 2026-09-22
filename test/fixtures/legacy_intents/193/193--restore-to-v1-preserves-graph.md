---
id: "193"
intent: "Make restore-to-v1 preserve the frontmatter graph: the owner rule that a completed intent is immutable (late rulings go to a NEW branch intent and the completed one is restored to v1) is currently carried out as a blunt whole-file revert, which also rolls back sources/chain edges that legitimately accrued AFTER v1 and that carry no delivered meaning; proven on intent 124, where new-intent correctly wrote the reciprocal chain += 131 in commit 8a8d505 and commit 60a51bf ('Restore intent 124 to v1: completed intents are immutable') then silently destroyed it, leaving an I1 reciprocity violation that went undetected for a week until a doctor sweep on 2026-07-13; one convention broke another, so define restore-to-v1 to roll back prose and lifecycle files while preserving the graph, which is metadata ABOUT OTHER INTENTS rather than content of this one"
sources: []
chain: []
created: 2026-07-13
author: claude-code
tags: ["plastic", "immutability", "graph", "restore", "project-plastic"]
---

## Intent
Make restore-to-v1 preserve the frontmatter graph: the owner rule that a completed intent is immutable (late rulings go to a NEW branch intent and the completed one is restored to v1) is currently carried out as a blunt whole-file revert, which also rolls back sources/chain edges that legitimately accrued AFTER v1 and that carry no delivered meaning; proven on intent 124, where new-intent correctly wrote the reciprocal chain += 131 in commit 8a8d505 and commit 60a51bf ('Restore intent 124 to v1: completed intents are immutable') then silently destroyed it, leaving an I1 reciprocity violation that went undetected for a week until a doctor sweep on 2026-07-13; one convention broke another, so define restore-to-v1 to roll back prose and lifecycle files while preserving the graph, which is metadata ABOUT OTHER INTENTS rather than content of this one

## Context

The owner's standing rule is: a completed intent is immutable. When a late ruling arrives after
completion, it goes into a NEW `--parent` branch intent, and the completed intent is restored to
its "v1" state (the state it was in when it was first marked delivered/abandoned, before any
in-place amendment). Today this restore has no tool and no written procedure anywhere in the
repo: it is a hand-run `git checkout`/whole-file revert, done from the owner's private
convention. Nothing in `PLASTIC.md`, any `skills/**/SKILL.md`, or `docs/` names it.

An intent file mixes two different kinds of content under one frontmatter block:
- PROSE (the `## Intent`, `## Context`, `## Outcome`, `## Insights` narrative, plus
  `checklist.md`/`outcome.md`/`spec.md`/`plan.md`): genuinely immutable after completion.
- GRAPH METADATA (`sources:`/`chain:` frontmatter arrays): metadata ABOUT OTHER INTENTS, not
  content of this one. It legitimately GROWS after completion, because a LATER intent's
  creation writes a reciprocal backlink into this one (invariant I1, defined in intent 68;
  `scripts/new-intent` already does this write correctly).

Proven incident: intent 124 was delivered 2026-07-06 (commit `aea4bfd`). Fifteen minutes later
it was amended in place (commit `01a3911`, a rule violation on its own — a late ruling landed as
an in-place edit instead of a new branch intent). Later the same day, creating intent 131 wrote
the correct I1 backlink (`chain: [] -> ["131"]`, commit `8a8d505`). Then the hand-run restore
(commit `60a51bf`, message "Restore intent 124 to v1: completed intents are immutable") reverted
the WHOLE intent file back toward its pre-amendment state, correctly undoing the `01a3911`
prose amendment, but ALSO destroying the `chain: ["131"]` edge that `8a8d505` had legitimately
and correctly written, replacing it with a value from the same stale snapshot. That left an I1
reciprocity violation (131 sourced 124, but 124's chain no longer held 131) undetected for a
full week, until a `doctor.rb` sweep on 2026-07-13 caught it. One convention (restore-to-v1)
silently broke another (I1 reciprocity). The incident and its manual repair are recorded
verbatim in `124--roadmap-delivery-collections/revisions.md` (Revisions v1-v3).

Facts established before Why (from `resources/discovery--restore-to-v1-preserves-graph.md`,
verified against store git history directly):
1. No restore-to-v1 code, script, or documented procedure exists anywhere in the repo. This
   intent must BUILD the tool and CODIFY the rule, not patch an existing script.
2. `scripts/lib/frontmatter_writer.rb` (`FrontmatterWriter.rewrite_arrays`) is a pure,
   style-preserving rewriter scoped to exactly the `sources:`/`chain:` frontmatter keys,
   leaving prose byte-identical. This is the surgical instrument for reapplying a graph onto
   v1 prose; reusing it means no new YAML rewriter is needed.
3. `scripts/doctor.rb` already detects this exact damage class (I1 reciprocity, I3
   disjointness, I4 dangling refs, and `## Links` projection drift). Detection existed;
   nothing in the restore path prevented the destruction, and nothing forced a check right
   after a restore.
4. Decisive constraint: `scripts/doctor.rb` (around the graph-invariant checks) states I2
   asymmetry (a chain entry with no reciprocal sources — a relational-only, non-formative
   edge) is intentionally NEVER auto-fixed; it is a legitimate edge shape, not a defect. A
   design that RE-DERIVES a restored intent's graph purely by scanning other intents for
   reciprocal edges would silently delete every legitimate I2 edge on that intent, trading one
   silent-destruction bug for another of the same shape. Re-derive-from-reciprocity is
   rejected on this basis (see Alternatives Considered in spec.md).
5. `scripts/rebuild-graph` + `scripts/lib/graph_rebuild.rb` already do store-wide graph repair
   (dedupe, I1 backlinks, I3 resolution, cross-store resolution). This intent does not
   duplicate that; it protects one intent's graph across a completed-intent restore.
6. Intent 107 defined `revisions.md` as the per-intent, append-only structural-maintenance
   audit trail. 124's `revisions.md` already carries v1-v3 documenting this very incident by
   hand; the new tool should append to that same trail automatically rather than inventing a
   new log surface.
7. Exact incident mechanics, confirmed directly from `~/.plastic` git history (not just the
   discovery doc's paraphrase): `aea4bfd` (intent 124 delivered) is the v1 anchor commit;
   `01a3911` (the violating in-place amendment) is the only commit between v1 and the restore
   that touched the intent's prose; `60a51bf` reverted the intent `.md`, `checklist.md`,
   `outcome.md`, and `spec.md` files, and in the same diff hunk swapped `chain: ["131"]` back
   to `chain: ["124a"]`, proving the revert was whole-file, not section-aware, and could not
   tell prose from graph metadata.
8. `## Links` is a pure projection of the frontmatter graph (intent 72), reprojected by
   `scripts/project-links`. If prose reverts to v1 but the graph is preserved at its current
   (post-v1) value, the v1 prose's own `## Links` body is stale the instant the restore
   completes and must be reprojected, not left as dead weight. Intent 192 is concurrently
   rewriting `scripts/project-links`, `scripts/lib/links_projection.rb`, and `hooks/create-gate`
   in this same session; 193 CALLS `project-links` as a subprocess/library dependency and does
   not edit any of those three files.
9. No delete/abandon verb anywhere unwinds a chain/sources backlink when an intent directory is
   deleted. This is 124's sibling symptom (124's chain pointed at a deleted 124b for a week)
   but it fires on a DIFFERENT trigger (directory deletion, not restore) and no intent today
   owns it.
10. A gate-review round raised, then this intent re-verified directly against `~/.plastic` git
    history, a claim that `60a51bf`'s `chain: ["124a"]` was "v1's chain" and that 124a's
    directory was later deleted. Both are false on direct verification: v1 itself (commit
    `aea4bfd`) held `chain: []`; `chain: ["124a"]` was a value the human hand-authored AT
    restore time, pointing to the newly-scaffolded branch intent 124a, which absorbed the four
    late rulings. 124a's directory (`124a--roadmap-project-root-and-timestamps`) was created
    shortly after the restore (`cde5bbe`) and is still active today (later commits `29be11c`,
    `83cd34d`, `d82ce9b` touch it); the directory that WAS deleted is 124b, a further branch of
    124a, confirmed absent from the store and from `INDEX.md`. So the real 124 incident never
    actually exhibited a v1 snapshot carrying a dangling edge. This does not invalidate the
    general engineering concern (a union COULD, in some other intent's restore, reintroduce an
    edge to a since-deleted target) which D14 below addresses on its own merits; it only means
    D14 is a general hardening, not something the 124 incident itself proves.

### Decisions

- D1. **The rule, stated plainly**: after an intent is completed (Done or Abandoned), its PROSE
  is immutable; its frontmatter GRAPH (`sources:`/`chain:`) is append-only and must survive a
  restore-to-v1 undamaged. The restore tool exists to CARRY this rule mechanically, not to
  loosen it: nothing about this fix licenses an agent to edit a completed intent's prose in
  place. The one-time-grant convention for editing completed intents (owner ruling, recorded in
  the owner's global memory) is unchanged; this intent only fixes what "restore" does to the
  graph.

- D2. **Mechanism: union, not re-derive.** The restore takes the v1 snapshot of the intent's own
  `.md` file (frontmatter + prose) as extracted from the store's git history, and REAPPLIES the
  graph on top of it: `desired_sources = v1_sources ∪ current_sources`,
  `desired_chain = v1_chain ∪ current_chain` (deduped, order-preserving, current-order-first),
  written via `FrontmatterWriter.rewrite_arrays(v1_content, sources: desired_sources, chain:
  desired_chain)`. `doctor.rb`'s I1 reciprocity check is used only as a CROSS-CHECK (reported in
  the restore's output), never as the source of truth for what the graph should contain.
  Rejected alternative: re-deriving the chain purely from scanning other intents' `sources` for
  reciprocal entries. Rejected because I2 asymmetry (fact 4 above) is a legitimate, non-
  reciprocal edge shape that a pure re-derive would silently erase, trading one silent
  graph-destroying bug for a structurally identical one. Union can never lose an edge that was
  present in EITHER snapshot; re-derive can silently lose edges that were never reciprocal by
  design.

- D3. **The union's cost, named and accepted.** A `sources`/`chain` edge added by the very
  amendment being reverted (present in `current` but not in `v1`) survives the restore. This is
  accepted: an unwanted surviving edge is VISIBLE and repairable by `doctor.rb`'s existing
  I1/I3/I4 checks and by `rebuild-graph`; a destroyed edge (the actual incident) is SILENT and
  unrecoverable without git archaeology. Prose immutability is unaffected either way, since this
  decision only concerns the two frontmatter arrays.

- D4. **Finding v1 is explicit, never guessed.** The tool takes a REQUIRED `--at <git-ref>`
  argument naming the commit in the store's git history whose version of the intent's files is
  v1. No commit-message heuristic, no auto-detection of "the delivery commit": the operator (or
  the orchestrator, on the owner's late-ruling ruling) names the ref explicitly, exactly as the
  124 incident's own `revisions.md` reconstruction already did by hand with exact commit SHAs
  (`aea4bfd`, `8a8d505`, `60a51bf`). This is the standard/boring option: git's own commit
  addressing is the source of truth, reused via `git show <ref>:<path>`; nothing new is
  invented to identify "the completed state." The tool FAILS LOUDLY (aborts, no partial write)
  if `--at` is missing, does not resolve to a commit in the store's history, or if the intent's
  own `.md` file did not exist at that ref.

- D5. **Scope of "the graph" is exactly `sources:`/`chain:`.** No other frontmatter field
  (`tags`, `author`, `created`, `id`) is treated as append-only graph metadata; those revert
  with the prose, matching `frontmatter_writer.rb`'s existing narrow edit surface and keeping
  the restore's blast radius to exactly the two arrays already proven to legitimately grow
  post-completion.

- D6. **CLI shape: dry-run by default, explicit `--apply`.** `scripts/restore-intent-v1
  <intent-id> --at <git-ref> [--plastic-home PATH] [--apply] [--audit-path PATH]`. With no
  `--apply`, the tool only COMPUTES and REPORTS: which files would revert to v1 content, a
  summary of what prose sections change, the v1 graph, the current graph, the resulting union,
  and any edge present in `current` but not in `v1` (the D3 cost, named explicitly per run).
  This inverts the sibling tools' convention (`rebuild-graph`/`project-links` default to a real
  run, opt into `--dry-run`) deliberately: restore-to-v1 is rarer and higher-blast-radius than
  routine graph repair, and this exact class of tool already destroyed live store data once.
  `--apply` performs the write and triggers the `project-links` reprojection and the
  `revisions.md` entry (D7).

- D7. **Every applied restore appends a `revisions.md` entry** in the target intent's own
  directory, following intent 107's append-only, move-and-record convention: which ref was used
  as v1, which files reverted, the before/after of `sources`/`chain` (the union math), and any
  current-only edge that survived. A new free-text violation tag `restored-to-v1` is used (the
  catalog explicitly allows free-text tags). This makes every restore self-documenting the same
  way 124's incident was reconstructed by hand after the fact, but automatically and at the time
  of the restore instead of a week later.

- D8. **Fail-loud conditions, no silent partial state.** The restore aborts before writing
  anything if: `--at` does not resolve; the intent id does not resolve to a directory; the v1
  content's frontmatter cannot be parsed; or the `FrontmatterWriter` rewrite does not confirm
  both arrays present in its output. If the file rewrite succeeds but the subsequent
  `project-links` reprojection subprocess fails, the tool does NOT roll back the frontmatter
  write (it is already correct and self-consistent) but prints a loud, unambiguous warning that
  `## Links` is now stale and names the exact command to rerun (`ruby scripts/project-links
  --plastic-home <home>`, which applies by default, no flag needed), rather than leaving the
  staleness unreported. This mirrors the severity `doctor.rb`'s
  `graph_links_projection` check already assigns to this drift.

- D9. **Sibling symptom (deleted-directory dangling backlink) is PARTIALLY addressed here, the
  rest stays PARKED.** D14 below means the restore path itself will never write or preserve an
  edge to a target it can positively confirm does not exist, and it reports one loudly every
  time it drops one. What remains PARKED is the general case: nothing unwinds a chain/sources
  edge at intent-DELETE time itself (checked: no `plastic-intent-ending` "delete" path, no
  `doctor.rb` auto-fix for this), because no delete/abandon verb exists in the repo to hook such
  a check into. D14 only guards the restore-time moment; it does not build a delete-time hook,
  which would widen 193's scope into inventing a mechanism this intent was not chartered to
  build. Recorded as a candidate follow-up intent (delete-time backlink unwind), not silently
  dropped and not silently absorbed.

- D10. **Testing is hermetic-only, against throwaway fixtures, never the live store.**
  `~/.plastic` is the owner's production data and this exact class of bug already destroyed
  part of it once. Every test spins up its own tmpdir git repository (precedent:
  `test/new_intent_test.rb`'s `git init` + `git worktree add` pattern), seeds it with a
  synthetic multi-commit history reproducing the 124/131 shape (create intent, deliver it as
  v1, write a legitimate later chain backlink, apply an in-place amendment, then invoke
  restore-intent-v1), and asserts on real fixture content, never a tautological "the code did
  what the code says" assertion. At minimum one test reproduces the OLD (whole-file-revert)
  failure mode against the fixture and shows the backlink is lost, and a second test proves the
  NEW tool preserves it through the same scenario.

- D11. Tier: M (one subsystem: one new script plus its library, calling two existing libraries
  and one existing CLI as a subprocess; no cross-cutting rework).

- D12. **The procedure must be documented, not just built.** A script nobody is pointed at does
  not prevent recurrence; discovery fact 1 (this procedure lives nowhere in the repo) is the
  root cause of the incident, not just background. Two doc surfaces, added by this intent:
  (a) `PLASTIC.md`, a short subsection under the existing "Terminal immutability" contract
  (the paragraph starting at line 624), stating in the codebase's own voice that after
  completion prose is immutable, the frontmatter graph is append-only and survives a restore,
  restore-to-v1 is performed by `scripts/restore-intent-v1`, and a hand-run whole-file `git
  checkout`/revert of a completed intent is FORBIDDEN because it silently destroys backlinks
  (citing the 124/131 incident in one clause); (b) `skills/intent-creating/SKILL.md`, one or
  two lines added to the "Decide Branch vs Root" section (lines 55-68, the `--parent`
  branch-intent path), stating that when a branch intent exists because a ruling arrived after
  the parent completed, the parent is restored via `scripts/restore-intent-v1`, never by hand.

- D13. **Restore-to-v1 runs under the maintenance lock; the tool does not enforce this itself.**
  `PLASTIC.md`'s terminal-immutability contract already states a terminal directory is
  writable only while a lock is held, and the maintenance lock (not the delivery lock) is the
  one covering sanctioned structural move-and-record edits after completion (108 D11, 112). A
  restore-to-v1 is exactly such an edit, so the procedure doc (D12) states restore-to-v1 runs
  under the maintenance lock. The TOOL itself does NOT acquire, check, or manage the lock:
  fail-open doctrine (111) means locks are never built into a tool as a trap, and lock
  acquisition/repair is the orchestrator's job, not a CLI's. `scripts/restore-intent-v1` prints
  one reminder line on `--apply` that the maintenance lock should be held; this is a courtesy
  message, not enforcement, so the fix cannot be misread as an end-run around the 112
  immutability gate.

- D14. **The union's output is target-resolved before writing, not written blind.** After
  computing the raw union (D2), every edge from EITHER snapshot is classified by reusing
  `GraphRebuild.resolve_ref` verbatim (the exact store-index/relocation-map machinery
  `rebuild-graph` and `doctor.rb` already share, so this tool can never disagree with them about
  what exists): an edge classified `:dead` (resolves to no id in any known store) is DROPPED
  from the written result and named loudly in the dry-run report, the apply report, and the
  `revisions.md` entry ("dropped dead edge -> X: target intent does not exist"); edges
  classified `:same_store`, `:cross_store`, or `:unknown_store` are all KEPT (bias always
  toward preserving an edge that might be real; only positive proof of non-existence justifies
  a drop, mirroring `GraphRebuild`'s own doctrine that "can't verify" is never treated as
  "gone"). This closes a general gap a pure union leaves open: in some OTHER intent's restore, a
  v1 snapshot could carry an edge to a directory that has since been deleted, and a naive union
  would silently reintroduce it. This is a general hardening, not a response to something the
  124 incident itself demonstrates (see Context item 10: 124's real v1 held `chain: []`, and
  124a was never deleted). Standard-solutions-first: no new resolution logic is written; the
  existing classifier is reused as-is.

## Outcome
A new restore-intent-v1 tool makes the rule explicit in code: prose is immutable after completion, the frontmatter graph is append-only and survives a restore; the old blunt whole-file revert destroyed correct backlinks that later intents had legitimately written

## Insights
(observations captured throughout — raw material for future intents)
2026-07-14T01:46:21Z · Exec · plastic-executor (autonomous) — Independent review caught two blocking bugs that unit tests missed because they only exercised the pure lib in isolation: (1) prose-sibling restore gated on File.exist? NOW instead of asking git what existed AT v1, silently never restoring a deleted sibling; (2) resolve_union kept the raw pre-resolution ref instead of GraphRebuild.resolve_ref's resolved value (classification[:id]/[:ref]), writing a stale ref that disagreed with rebuild-graph/doctor. General lesson: any consumer of GraphRebuild.resolve_ref must write the resolved id/ref, never the original lookup key; the original ref is only valid for reporting a before-value, never for the write path.
2026-07-14T01:46:30Z · Exec · plastic-executor (autonomous) — Reviewer's required-fix batch: a fail-loud confirmation check that only greps for substrings (sources: / chain: appearing anywhere) is not a confirmation; D8-style write-confirmation must re-parse the actual written content and assert the parsed values equal the computed result. A store-wide side effect triggered by a per-intent operation (project-links reprojecting every intent's ## Links as a side effect of restoring one) must be announced explicitly before it runs, not left implicit in a doc comment, plus given an explicit opt-out flag. Also: an approach narrative in spec.md that describes a mechanism not backed by a Decision or an AC (the doctor.rb I1 post-hoc cross-check) is a promise nothing enforces; amend the spec to match what shipped rather than leave the gap standing.

## Links
<!-- No sources or chain; this intent has no graph edges to project. -->
