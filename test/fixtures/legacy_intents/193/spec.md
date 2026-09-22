Tier: M
# Spec: Restore-to-v1 preserves the frontmatter graph

## Problem

The owner's rule that a completed intent is immutable (a late ruling goes to a new `--parent`
branch intent, and the completed intent is restored to its v1 state) has no tool and no written
procedure anywhere in the repo. It is carried out by hand as a whole-file `git checkout`/revert.
That whole-file revert cannot distinguish an intent file's two different kinds of content: PROSE
(the narrative, genuinely immutable after completion) and GRAPH METADATA (the `sources:`/
`chain:` frontmatter arrays, metadata about OTHER intents, which legitimately grows after
completion whenever a later intent's creation writes a reciprocal backlink into this one).
Proven on intent 124: commit `8a8d505` (creating intent 131) correctly wrote `chain: ["131"]`
into 124; commit `60a51bf` ("Restore intent 124 to v1") then reverted the whole file, silently
destroying that edge and leaving an I1 reciprocity violation undetected for a week, until a
`doctor.rb` sweep caught it on 2026-07-13. One convention (restore-to-v1) silently broke another
(I1 reciprocity, defined in intent 68). Nothing today prevents this from recurring on the next
late ruling.

## Goals

- Build a mechanized, documented restore-to-v1 tool: today none exists (the procedure has only
  ever lived as the owner's private convention), so this is a new tool, not a patch.
- The tool reverts an intent's prose-bearing files (its own `.md` narrative, `checklist.md`,
  `outcome.md`, `spec.md`, `plan.md` if present) to their content at an explicit v1 anchor
  commit, while never losing a `sources`/`chain` frontmatter edge that exists at the time of the
  restore.
- The frontmatter graph after a restore is the UNION of the v1 snapshot's `sources`/`chain` and
  the current snapshot's `sources`/`chain`, classified edge-by-edge against whether each target
  intent actually exists (D14): an edge whose target is confirmed gone is excluded and reported,
  never silently resurrected; an edge that cannot be confirmed either way is kept. The restore
  never subtracts a live edge.
- `## Links` is reprojected (via `scripts/project-links`, called not edited) immediately after
  an applied restore, so it never goes stale relative to the preserved graph.
- The restore is dry-run by default and reports exactly which prose sections would change and
  exactly which graph edges are kept, before any write happens; `--apply` is required to write.
- Every applied restore appends a `revisions.md` entry recording the v1 ref used, the files
  reverted, and the before/after of `sources`/`chain`.
- The tool fails loudly and aborts with no partial write whenever it cannot identify v1, cannot
  parse the current frontmatter, or cannot confirm the graph was carried into its output.
- Reproduce the 124/131 backlink loss against a hermetic fixture under the OLD (whole-file
  revert) behavior, then prove the NEW tool preserves the backlink through the same scenario.
- Document the procedure itself, not only the tool: a short `PLASTIC.md` subsection under the
  existing "Terminal immutability" contract naming `scripts/restore-intent-v1` as the only
  sanctioned restore path and forbidding a hand-run whole-file revert, plus one or two lines in
  `skills/intent-creating/SKILL.md`'s branch-intent path stating that a late-ruling branch
  intent's parent is restored via this tool, never by hand.
- State that restore-to-v1 runs under the maintenance lock (the existing terminal-immutability
  contract's own lock, not a new one), documented in the procedure doc; the tool itself prints a
  one-line reminder on `--apply` rather than acquiring or checking the lock.

## Non-Goals

- Re-deriving a restored intent's graph from other intents' reciprocal `sources` entries.
  Rejected: `doctor.rb` treats I2 asymmetry (a chain entry with no reciprocal sources) as a
  legitimate, non-reciprocal edge shape that is never auto-fixed; a pure re-derive would
  silently delete every such edge on the restored intent, reproducing the same class of silent
  destruction this intent exists to fix.
- Auto-detecting or guessing which commit is "v1" from commit-message text or INDEX.md history.
  The v1 anchor is always an explicit `--at <git-ref>` argument.
- Store-wide graph repair. `scripts/rebuild-graph` already does dedupe, I1 backlinks, I3
  resolution, and cross-store resolution across the whole store; this intent protects one
  intent's graph across one restore operation, it does not duplicate or replace rebuild-graph.
- Editing `scripts/project-links`, `scripts/lib/links_projection.rb`, or `hooks/create-gate`.
  Intent 192 is concurrently rewriting these in this session; 193 calls `project-links` as a
  subprocess/library dependency only.
- Loosening completed-intent immutability. The one-time-grant convention for editing a
  completed intent's prose is unchanged; this tool only changes what "restore" does to the
  frontmatter graph, it does not create a new path for agents to edit completed intents' prose.
- Building a general delete-time backlink unwind (the deleted-directory sibling symptom: 124's
  chain once pointed at a deleted 124b). This intent's target-resolution safeguard (the union
  goal above) means the restore path itself never writes or preserves a confirmed-dead edge, which
  partially covers the symptom at restore time, but nothing here unwinds a backlink at the
  moment a directory is DELETED, since no delete/abandon verb exists anywhere to hook such a
  check into. Building that hook is parked as a candidate follow-up intent, not merged in here.
- Building lock acquisition, checking, or management into the tool. The maintenance lock is
  named in the procedure doc as the lock restore-to-v1 runs under; the tool only prints a
  reminder, per fail-open doctrine (111): locks are the orchestrator's job, never built into a
  CLI as a trap.
- Running any test against the live `~/.plastic` store. All tests run against hermetic tmpdir
  git fixtures.

## Approach

Add a new script, `scripts/restore-intent-v1`, plus its pure logic library (e.g.
`scripts/lib/restore_intent_v1.rb`), following the existing `rebuild-graph`/`project-links`
shape: a thin CLI shell doing discovery/IO/reporting, and a pure, testable transform module
doing the actual graph math.

The CLI resolves `<intent-id>` to its on-disk directory (reusing existing store-discovery/
intent-resolution helpers, the same ones `rebuild-graph`, `project-links`, and `doctor.rb`
already share, so this tool can never disagree with them about where an intent lives).
`--at <git-ref>` is required and names the commit whose version of the intent's files is v1;
the tool extracts that version via `git show <ref>:<path>` for each of the intent's own `.md`
file plus `checklist.md`, `outcome.md`, `spec.md`, and `plan.md` (whichever exist at that ref).

Only the intent's own `.md` file carries frontmatter, so only it needs graph-aware handling.
The rest revert as plain whole-file swaps to their v1 content, matching current behavior exactly
(they carry no `sources`/`chain` to lose). For the `.md` file: the tool parses the CURRENT
file's `sources`/`chain` and the v1 snapshot's `sources`/`chain`, computes
`desired_sources = v1_sources ∪ current_sources` and `desired_chain = v1_chain ∪ current_chain`
(deduped, current-order-first), and writes the result by calling
`FrontmatterWriter.rewrite_arrays(v1_content, sources: desired_sources, chain: desired_chain)`
from the existing `scripts/lib/frontmatter_writer.rb`. This yields v1's exact prose with only
the two graph arrays updated to the union; no new YAML rewriter is written.

Before the union is written, every edge in it (from either snapshot) is target-resolved by
reusing `GraphRebuild.resolve_ref(ref, referer_store:, relocation_map:, store_index:)` verbatim,
the exact classifier `rebuild-graph` and `doctor.rb` already share (built from `StoreDiscovery`
and each store's `## Relocated` log, so this tool can never disagree with them about what
exists). A `:dead` classification (the target id is absent from every known store) drops the
edge from the written result and names it explicitly in the dry-run report, the apply report,
and the `revisions.md` entry. `:same_store`, `:cross_store`, and `:unknown_store` are all kept:
bias always runs toward preserving an edge that might be real, and only positive proof of
non-existence justifies a drop, exactly matching `GraphRebuild`'s own doctrine that an unknown
store is never treated as a dead one. This closes a general gap a pure union leaves open (some
future restore's v1 snapshot could carry an edge to a directory since deleted); it is not a
response to the 124 incident itself, whose real v1 snapshot held `chain: []`, not a stale
dangling edge, verified directly against store git history.

Dry-run is the default. It prints: which files would change, a summary of the prose diff, the
v1 graph, the current graph, the resulting union, and any edge that exists in `current` but not
in `v1` (an edge added by the very change being reverted, which will now survive; named
explicitly every run so it is never a silent side effect). `--apply` performs the writes, then
shells out to `scripts/project-links` (calling it, not editing it) to reproject `## Links` for
the restored intent so the projection matches the preserved graph, then appends a `revisions.md`
entry in the target intent's own directory (intent 107's convention): the v1 ref, the files
reverted, the before/after of `sources`/`chain`, and a new free-text tag `restored-to-v1` (the
revisions.md catalog explicitly allows free-text tags).

The tool fails loudly and writes nothing if: `--at` is missing or does not resolve to a commit
in the store's git history; the intent id does not resolve to a directory; the v1-snapshot
content's frontmatter cannot be parsed; or `FrontmatterWriter`'s output does not contain both
arrays as expected. If the frontmatter write succeeds but the `project-links` reprojection
subprocess exits non-zero, the tool does not roll back the (already-correct) frontmatter write,
but prints an unmissable warning naming `## Links` as stale and the exact command to rerun.

Two documentation edits complete the picture (the tool alone does not prevent recurrence if
nobody is pointed at it): a short subsection in `PLASTIC.md` under the existing "Terminal
immutability" contract (the paragraph at line 624) states the rule in the codebase's own voice
and forbids a hand-run whole-file revert of a completed intent, naming `scripts/restore-intent-v1`
as the only sanctioned path; and one or two lines added to `skills/intent-creating/SKILL.md`'s
"Decide Branch vs Root" section (lines 55-68) state that a late-ruling branch intent's parent is
restored via this tool, never by hand. The `PLASTIC.md` addition also states that restore-to-v1
runs under the maintenance lock, the same lock the terminal-immutability contract already names
as covering sanctioned structural edits after completion; the tool itself does not acquire or
check this lock (fail-open doctrine, 111: lock management is the orchestrator's job, never built
into a CLI), it only prints a one-line reminder on `--apply`.

Tests are hermetic: each test builds its own tmpdir git repository (the pattern already used by
`test/new_intent_test.rb`: `git init`, then commits, then `git worktree add` where a working
copy is needed), seeds a synthetic history shaped like the 124/131 incident (create intent A,
commit as "delivered" = v1; create intent B whose `sources` includes A, which correctly writes
A's `chain` backlink; then an in-place prose amendment to A). One test drives the OLD
(whole-file-revert) behavior against this fixture and asserts the backlink is lost, proving the
regression is real and reproducible, not hypothetical. A second test drives the NEW tool over
the identical fixture and asserts the backlink survives and the prose matches v1 exactly. Two
further tests exercise target resolution (D14) on separate, honestly-labeled synthetic
fixtures, not framed as a replay of the real incident (verified directly against git history:
124's actual v1 held `chain: []`, no dangling edge ever existed in it): one seeds a v1 chain
containing an edge to an intent id that has no directory in the fixture, and asserts the
restored file excludes it while the drop is named in the report and in `revisions.md`; the
other combines that dead v1 edge with a live, legitimately-accrued current-only edge and asserts
the restored chain contains exactly the live edge, nothing else.

The Links assertion in the test suite is direct, not subprocess-coupled: because the `## Links`
projection is deterministic (intent 72), the primary test assertion computes and checks the
expected rendered body text directly against the restored file, rather than shelling out to
`scripts/project-links` to verify. `scripts/project-links` is rewritten concurrently by intent
192 in this same session, so a test that depended on its current CLI surface would be brittle by
construction. The TOOL itself still calls `project-links` for real at `--apply` time (that
coupling is correct and required by Goal 4); any project-links subprocess invocation FROM A TEST
is secondary, always passes an explicit `--dry-run` and a `--plastic-home` scoped to the test's
own tmpdir fixture (never the real store), because `project-links` applies by default and an
unknown flag triggers a full store-wide apply.

## Alternatives Considered

| Alternative | Not chosen because |
|---|---|
| Re-derive the restored intent's chain purely from scanning other intents' sources for reciprocal entries | I2 asymmetry (a chain entry with no reciprocal sources) is a legitimate, non-reciprocal edge shape doctor.rb never auto-fixes; a pure re-derive would silently delete every such edge, reproducing the same class of silent destruction this intent exists to fix |
| Auto-detect the v1 commit from commit-message patterns (for example "intent N delivered") | Fragile: relies on message-text conventions that are not enforced anywhere, and a wrong guess would restore against the wrong anchor with no operator in the loop to catch it; the standard, boring option is to let the operator name the exact git ref, exactly as the 124 incident's own revisions.md reconstruction already did by hand |
| Default the CLI to a real run, matching rebuild-graph and project-links (opt into --dry-run) | Restore-to-v1 is rarer and higher-blast-radius than routine graph repair, and this exact class of tool already destroyed live store data once; defaulting to dry-run forces a deliberate --apply before any write |
| Merge the deleted-directory dangling-backlink sibling symptom into this intent | Different trigger event (directory deletion, not a completed-intent restore) and no delete/abandon verb exists today to hook a fix into; widening scope here would mean inventing a delete-time hook this intent was not chartered to build |
| Write a new general-purpose frontmatter YAML rewriter for this tool | scripts/lib/frontmatter_writer.rb already does exactly this, scoped to sources/chain, style-preserving, and proven in rebuild-graph; reusing it is the standard/boring choice over inventing a second rewriter |
| Write a new target-existence resolver for the union | GraphRebuild.resolve_ref already classifies same_store, cross_store, dead, and unknown_store using StoreDiscovery and each store's Relocated log; reusing it verbatim is the standard/boring choice and guarantees this tool can never disagree with rebuild-graph or doctor.rb about what exists |
| Build maintenance-lock acquisition or checking into the tool itself | Fail-open doctrine (111): the lock system never traps a session, and lock acquisition/repair is the orchestrator's job, not a CLI's; the procedure doc names the lock and the tool prints a courtesy reminder instead |
| Verify the restored `## Links` body by shelling out to `scripts/project-links` in the test suite | That script's CLI surface is being rewritten concurrently by intent 192 in this session; a test coupled to its flags would be brittle by construction, so the primary test assertion checks the deterministic projected text directly, and any project-links subprocess call is secondary and test-scoped |

## Decisions

- D1. The rule: after completion, prose is immutable; the frontmatter graph (`sources`/`chain`)
  is append-only and must survive a restore. The tool carries this rule; it does not loosen
  completed-intent immutability or license in-place prose edits.
- D2. Mechanism is union (v1 graph ∪ current graph), written via `FrontmatterWriter.rewrite_arrays`
  onto the v1 prose snapshot. Re-derive-from-reciprocity is rejected because I2 asymmetry is a
  legitimate edge shape a re-derive would silently erase.
- D3. The union's cost (a current-only edge, added by the very change being reverted, survives
  the restore) is accepted: a surviving unwanted edge is visible and doctor-repairable; a
  destroyed edge is silent and unrecoverable.
- D4. v1 is identified only via an explicit, required `--at <git-ref>` argument; never guessed
  from commit messages or INDEX history. The tool fails loudly if the ref does not resolve.
- D5. "The graph" scope is exactly the `sources:`/`chain:` frontmatter keys; every other
  frontmatter field reverts with the prose.
- D6. CLI is dry-run by default, `--apply` required to write; this deliberately inverts the
  rebuild-graph/project-links default-apply convention given this tool's higher blast radius.
- D7. Every applied restore appends a `revisions.md` entry (v1 ref, files reverted,
  sources/chain before/after) using a new free-text tag `restored-to-v1`.
- D8. Fail-loud, no partial writes, on any of: unresolved `--at`, unresolved intent id,
  unparseable v1 frontmatter, or an unconfirmed graph write. A post-write `project-links`
  reprojection failure is reported loudly (with the exact rerun command) but does not roll back
  the already-correct frontmatter write.
- D9. The deleted-directory dangling-backlink sibling symptom is explicitly parked as a
  candidate follow-up intent, not merged into this one and not silently dropped.
- D10. All tests run against hermetic tmpdir git fixtures (the `test/new_intent_test.rb`
  `git init`/`git worktree add` pattern), never against the live `~/.plastic` store; at least
  one test reproduces the old failure mode before proving the new tool's fix.
- D11. Tier: M.
- D12. The procedure is documented, not only built: a `PLASTIC.md` subsection under "Terminal
  immutability" (line 624) naming `scripts/restore-intent-v1` as the sole sanctioned path and
  forbidding a hand-run whole-file revert; and one or two lines in
  `skills/intent-creating/SKILL.md`'s branch-intent path (lines 55-68) pointing a late-ruling
  branch intent's restore at the same tool.
- D13. Restore-to-v1 runs under the maintenance lock, stated in the procedure doc; the tool does
  not acquire, check, or manage the lock itself (fail-open doctrine, 111), it only prints a
  one-line reminder on `--apply`.
- D14. The union is target-resolved before it is written, reusing `GraphRebuild.resolve_ref`
  verbatim: a `:dead` edge is dropped and reported (dry-run, apply, and `revisions.md`); a
  `:same_store`, `:cross_store`, or `:unknown_store` edge is kept and, if `:unknown_store`,
  reported as unverified. This is a general hardening, grounded in the abstract risk a pure
  union leaves open, not in the 124 incident itself, whose real v1 snapshot held `chain: []`
  with no dangling edge, confirmed directly against store git history.

## Acceptance Criteria

- [ ] `scripts/restore-intent-v1` exists, requires `<intent-id>` and `--at <git-ref>`, and
      accepts `--plastic-home`, `--apply`, `--audit-path` following the `rebuild-graph`/
      `project-links` flag-naming convention.
- [ ] Running without `--apply` (dry-run) performs no filesystem write and prints: the files
      that would change, the v1 graph, the current graph, the resulting union, and any
      current-only edge.
- [ ] Running with `--apply` reverts the intent's own `.md` file to v1 prose while its
      `sources`/`chain` frontmatter equals the union of the v1 and current arrays (verified by
      reading the written file back and diffing prose against the v1 git blob byte-for-byte
      outside the two frontmatter array lines).
- [ ] Running with `--apply` reverts `checklist.md`, `outcome.md`, `spec.md`, and `plan.md` (any
      that exist at the v1 ref) to their exact v1 byte content.
- [ ] A hermetic test reproduces the 124/131 incident shape (v1 delivery, a later intent's
      correct chain backlink, an in-place amendment) and shows the OLD whole-file-revert
      approach destroys the backlink.
- [ ] A hermetic test proves the NEW tool, run over the identical fixture and history, preserves
      the backlink through the restore.
- [ ] A hermetic test seeds a v1 chain containing an edge to an intent id with no directory in
      the fixture, and asserts: the restored file's chain excludes that edge, the drop is named
      in the dry-run and apply output, and it is recorded in the `revisions.md` entry.
- [ ] A hermetic test combines that dead v1 edge with a live, legitimately-accrued current-only
      edge, and asserts the restored chain contains exactly the live edge and nothing else.
- [ ] After an applied restore, `## Links` in the target intent's file equals the expected
      rendered projection text, computed and asserted directly in the test (the projection is
      deterministic); this is the primary assertion. Any `scripts/project-links` subprocess
      invocation is secondary, passes an explicit `--dry-run` and a `--plastic-home` scoped to
      the test's own tmpdir, and is never the sole basis for the assertion.
- [ ] After an applied restore, the target intent's `revisions.md` gains exactly one new entry
      tagged `restored-to-v1` naming the `--at` ref, the reverted files, the sources/chain
      before/after, and any dropped dead edge.
- [ ] The tool aborts with a non-zero exit and no filesystem write when `--at` does not resolve
      to a commit, when the intent id does not resolve to a directory, or when the v1 snapshot's
      frontmatter cannot be parsed.
- [ ] Running `scripts/restore-intent-v1 ... --apply` prints a one-line reminder naming the
      maintenance lock; the tool does not call any lock-acquisition or lock-check code path.
- [ ] `PLASTIC.md` gains a subsection under "Terminal immutability" naming
      `scripts/restore-intent-v1` as the sole sanctioned restore path, forbidding a hand-run
      whole-file revert, stating the graph is append-only across a restore, and naming the
      maintenance lock as the lock a restore runs under.
- [ ] `skills/intent-creating/SKILL.md`'s "Decide Branch vs Root" section states that a
      late-ruling branch intent's parent is restored via `scripts/restore-intent-v1`, never by
      hand.
- [ ] No test in the new test file touches `~/.plastic`; every test constructs its own tmpdir
      git repository.
- [ ] `bin/test` passes with the new test file included.
- [ ] No em-dashes introduced in any new code comment, doc line, or commit message (hyphens
      only).

## Open Questions

None
- D1-D14 above resolve every question raised during discovery and gate review: where the
  procedure lives (D1, new script, plus D12's doc surfaces), the mechanism argument (D2, D3),
  how v1 is found (D4), frontmatter scope (D5), CLI shape (D6), the revisions.md audit trail
  (D7), fail-loud behavior (D8), the deleted-directory sibling symptom (D9, partially addressed
  by D14, the rest parked explicitly), the testing discipline (D10), the two documentation
  surfaces (D12), the maintenance-lock procedure (D13), and target resolution on the union
  (D14).
