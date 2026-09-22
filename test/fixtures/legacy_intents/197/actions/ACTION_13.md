# ACTION_13 - the three live proof-case repairs, through maintenance-run; final verification

Depends on ACTION_9 (`scripts/maintenance-run`), ACTION_12 (doctrine describes what actually
exists). Covers spec.md's three proof-case ACs plus "each repair was made by branching...
never by a manual Edit/Write... and never left stranded" plus "a doctor run after all three
repairs reports zero `graph_links_projection` warnings for ids 26, 3b, and 15."

**This action mutates `~/.plastic` (the real global store), never the plastic code
worktree.** Run every command below with `RbConfig.ruby` pointed at the WORKTREE's own copy of
`scripts/maintenance-run` (so the tool under test, built in ACTIONS 1-9, is the one actually
used), but with `--plastic-home` defaulting to the real `~/.plastic` (do not pass
`--plastic-home` to a tmp dir for this action; the whole point is repairing the real store).
Example invocation shape: `ruby /Users/zlatko/apps/personal/plastic/.claude/worktrees/197--separate-maintenance-from-work/scripts/maintenance-run --tool project-links --intent 26 --store global --apply`.

**Precondition, per plan.md's Risk note:** `git -C ~/.plastic status --porcelain` must be empty
before starting (verified dirty today: `.cache/update-check.json`, `manifest.json`, an audit
dry-run file). Commit or stash those first; `MaintenanceGit`'s precheck (ACTION_8) refuses
loudly otherwise, correctly.

**Load-bearing correctness note (verified live, see ACTION_1's own finding): ids `26` and `15`
BOTH collide across stores** (`26` also exists in `mihradesign` and `plastic`'s own stores;
`15` also exists in `mihradesign` and `plastic`'s own stores). Every command below passes an
explicit `--store <key>` for this reason - never rely on bare-id auto-resolution for these
three repairs, even though `3b`/`3a` happen not to collide today.

## 13a. Global 26: reproject Links (adds the one real line, drops nothing)

```
ruby <worktree>/scripts/maintenance-run --tool project-links --intent 26 --store global --apply
```
Expected: `## Links` in `~/.plastic/store/26--ai-agents-resources/26--ai-agents-resources.md`
changes from the stale "No sources or chain" comment to the one real
`[[ai-agents-resources:1|...]]` line (discovery's citation:
`26--ai-agents-resources.md:4-5` chain already has this edge; only the Links TEXT was stale).
A `revisions.md` appears in that directory for the first time, `## Revision v1`, `[rule:
links-projection]`. Commit lands on `~/.plastic`'s main via the branch-and-merge-back
mechanism; confirm with `git -C ~/.plastic log --oneline -3` showing a merge commit naming
`project-links --intent 26`.

## 13b. Dealintell 3b: reproject Links (drops the 3 malformed lines, keeps the real one)

```
ruby <worktree>/scripts/maintenance-run --tool project-links --intent 3b --store project:dealintell --apply
```
Expected: `~/.plastic/projects/dealintell/store/3b--seller-listing-submission/3b--seller-listing-submission.md`'s
`## Links` keeps its `3--service-pivot` line (backed by `sources: ["3"]`) and loses the three
single-dash malformed lines (`3d-payments-subscription-gating`, `3c-legal-shield-and-network`,
`3e-buyer-seller-connection`) - they resolve to nothing (real dirs are double-dash), so
ACTION_2's `dead` bucket reports them in the audit, and they are still dropped from the file
(per the owner's own verified note: "reprojection destroys nothing... the bug is the SILENCE,
not the deletion" - dropping genuine junk is correct; only the prior silence was the bug). A
`revisions.md` receipt appears on 3b, `[rule: links-projection]`, naming all three drops in
its `Change` text.

## 13c. Dealintell 15/3a: add the missing reciprocal edge, then reproject both

**Deliberately does NOT invoke `rebuild-graph`.** `rebuild-graph` is store-wide with no
single-id scope; running it for real (`--apply`) across the WHOLE store family to fix one pair
of intents risks sweeping in unrelated pre-existing drift anywhere else in the store (a scope
expansion this intent's own D15 "no fragmentation" and the spec's tight proof-case framing
both argue against). Since asserting the NEW edge itself (rather than fixing an existing one)
is exactly the class of maintenance D8(a) reserves for the curator ("a frontmatter chain/sources
edge that points to... a missing required edge"), this step goes through the curator's own
documented mechanism (ACTION_7), not `maintenance-run`.

Per ACTION_7's step 7 (detect-lock, clean-tree, branch, edit-plus-receipt, scoped-commit,
merge-back), as the `plastic-intent-curator` agent (or a session following the identical
recipe by hand):

1. Confirm `ruby ~/.plastic/scripts/plastic-lock status --intent-dir ~/.plastic/projects/dealintell/store/15--competitive-landscape-comp-pack` and the same for `3a--competitor-pricing-research` both report `"lock_fresh": false` (neither is mid-delivery).
2. Confirm `git -C ~/.plastic status --porcelain` is empty (13a/13b's own commits already
   landed cleanly, so this should already hold).
3. `git -C ~/.plastic checkout -b maintenance/curator-15-3a-<timestamp> main`.
4. Edit `15--competitive-landscape-comp-pack.md` frontmatter: `sources: []` -> `sources:
   ["3a"]` (its `## Links` line to `3a--competitor-pricing-research` is real, per discovery;
   the frontmatter is what was missing).
5. Edit `3a--competitor-pricing-research.md` frontmatter: `chain: []` -> `chain: ["15"]` (I1
   reciprocity: 15 sourcing from 3a in the SAME store means 3a's chain must carry 15 back).
6. Append a `revisions.md` entry to `15--competitive-landscape-comp-pack`'s own directory:
   `## Revision v1`, `- Why: missing documented-real sources edge to its own research origin
   [rule: missing-reciprocity]`, `- Prior location: ...md frontmatter - sources`, `- Change:
   added "3a" (before: [] -> after: ["3a"])`.
7. Append a `revisions.md` entry to `3a--competitor-pricing-research`'s own directory: `##
   Revision v1` (or next available `vN` if one already exists), `- Why: missing I1 reciprocity
   backlink to 15, which sources from it [rule: missing-reciprocity]`, `- Prior location:
   ...md frontmatter - chain`, `- Change: added "15" (before: [] -> after: ["15"])`.
8. `git -C ~/.plastic add -- projects/dealintell/store/15--competitive-landscape-comp-pack/15--competitive-landscape-comp-pack.md projects/dealintell/store/15--competitive-landscape-comp-pack/revisions.md projects/dealintell/store/3a--competitor-pricing-research/3a--competitor-pricing-research.md projects/dealintell/store/3a--competitor-pricing-research/revisions.md` (never `-A`), then commit.
9. `git -C ~/.plastic checkout main && git -C ~/.plastic merge --no-ff maintenance/curator-15-3a-<timestamp> && git -C ~/.plastic branch -d maintenance/curator-15-3a-<timestamp>`.

Then reproject both sides through the tool (now that frontmatter carries the real edge):
```
ruby <worktree>/scripts/maintenance-run --tool project-links --intent 15 --store project:dealintell --apply
ruby <worktree>/scripts/maintenance-run --tool project-links --intent 3a --store project:dealintell --apply
```
Expected: `15`'s `## Links` gains the `3a--competitor-pricing-research` line (from its own new
`sources`); `3a`'s `## Links` gains the `15--competitive-landscape-comp-pack` line (from its
own new `chain`). Each of these two `project-links` runs writes ITS OWN `links-projection`
receipt too (`## Revision v2` on each, since step 6/7 above already wrote each directory's
`v1`) - this is correct and expected, not a duplicate: step 6/7's entry documents the
FRONTMATTER assertion; the tool's own v2 documents the LINKS TEXT regeneration that followed
from it. Two honest, distinct changes, two honest, distinct entries.

## 13d. Verify: doctor reports zero graph_links_projection warnings for 26, 3b, 15

```
ruby <worktree>/scripts/doctor.rb
```
(or `--store global` / `--store dealintell` scoped runs). Parse the JSON `checks` array for
`name == "graph_links_projection"`; confirm its `status` is `"pass"` and, if `"details"` is
present, none of the three ids (`26`, `3b`, `15`) appear in it. This is the spec's own AC;
treat any remaining detail line naming one of the three as this action NOT DONE, not as an
acceptable residual.

## 13e. Final suite, em-dash guard, branch-only confirmation

1. From the code worktree: `ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'`, green, run/assertion count at or above the 1557/5318 baseline (plan.md).
2. `git -C <worktree> diff main...HEAD` (or `git log --oneline` since branching) and confirm
   no em-dash (Unicode codepoint U+2014) was introduced in any added line: pipe the diff
   through a filter for added lines only (`grep '^+'`) and search for the UTF-8 bytes of
   U+2014; a zero-result search is the pass condition. Use a Ruby one-liner if the shell
   mangles the byte sequence: `ruby -e 'exit(File.read(ARGV[0]).include?(["e2","80","94"].map{|h|h.to_i(16)}.pack("C*").force_encoding("UTF-8")) ? 1 : 0)'`
   against a saved diff file (builds the U+2014 character from its codepoint bytes rather
   than embedding the character literally in this action file).
3. Confirm the worktree's own git state: still on `plastic/197--separate-maintenance-from-work`, NOT merged into the code repo's `main`, no `plastic-releasing` run. `git -C <worktree> log main..HEAD --oneline` should show every commit this intent added; `git -C /Users/zlatko/apps/personal/plastic log HEAD..plastic/197--separate-maintenance-from-work --oneline` (run from the main checkout) should be non-empty and main's own tip must be unchanged by this intent's work.
4. Confirm the untouched non-goals: `git -C <worktree> diff main...HEAD --stat` names no
   change to `scripts/lib/legacy_bookend_amnesty.rb`, no change to the `signals_complete`
   check in `scripts/doctor.rb` beyond ACTION_11's fix_hint sentence, and no packaging-rule
   change in `package.json`'s `files` array (all three are intent 211's scope, D19/spec
   Non-Goals).

## 13f. Sequencing note for the ending stage (not authored by Exec itself)

`outcome.md` is an End-stage deliverable (`plastic-intent-ending`), not an Exec artifact - this
action does NOT write it. Leave this exact content ready for whoever runs the ending skill, so
the required AC ("197's merge commit or outcome.md records this ordering") is satisfied without
guessing the wording later:

> This intent stays on branch `plastic/197--separate-maintenance-from-work`, not merged.
> Merge sequencing: intent 178 (store worktrees) must be Completed and merged to main FIRST;
> 197 merges after, and both release together as one batch (D16/D17). The three live
> `graph_links_projection` proof-case repairs (global 26, dealintell 3b, dealintell 15) are
> STORE-side changes, already committed and merged to `~/.plastic`'s own main independently of
> this code branch (see ACTION_13); they do not wait on 178 or on this branch's own merge.

## Verify

Full suite green (13e.1), zero em-dash (13e.2), branch-only confirmed (13e.3), non-goals
untouched (13e.4), doctor clean on 26/3b/15 (13d). All 18 spec.md acceptance criteria checked
off in `checklist.md` at this point.
