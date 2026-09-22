# Doctor-consistency roadmap: decision and release cut Implementation Plan

> **For agentic workers:** Use `plastic-intent-executing` to implement this plan task-by-task.

**Goal:** Confirm the nine collected intents (187-194, 196) are genuinely delivered, cut and
publish Plastic 1.4.0, record the doctor's real live result (not a false clean pass), close the
`doctor-consistency` roadmap honestly, carry the pending dealintell Links repair as a visible
open item, record the batch's two mechanism-level lessons in intent 195's own outcome.md, and
complete intent 195.

**Architecture:** No code changes. Two actions, run in order. `actions/ACTION_1.md` (Task 1) is
the release cut: bump three version files in lockstep, add one CHANGELOG entry, tag, push,
publish to npm's `latest` dist-tag, cut the GitHub release with the Latest badge, verify all
three surfaces (npm, GitHub, git tag) agree. `actions/ACTION_2.md` (Task 2) runs after Task 1
lands: re-confirms the nine intents' delivery, syncs the local install and re-runs the doctor to
prove `hooks_match_registry` actually clears, closes the roadmap (the 194 checkbox, one closing
Log entry recording the true partial result, `## Goal` left untouched), writes intent 195's real
`outcome.md` (nine-intent confirmation, doctor before/after, the two lessons, the open dealintell
item), cleans up 195's own worktrees, and completes intent 195 via `scripts/end-intent`. The
pending dealintell Links repair is tracked as an explicit open item in both the checklist and
outcome.md and is never executed by either action.

**Tech Stack:** git, npm, `gh` CLI, the three JSON/Markdown version files already used by every
prior Plastic release.

**Intent:** 195: Roadmap: the doctor-consistency batch

**Tier:** S

---

## Preconditions (already true, not part of this task)

These are established facts from spec.md, not steps this plan performs:

- All nine collected intents (187, 188, 189, 190, 191, 192, 193, 194, 196) show
  `disposition: delivered` in their own `outcome.md`, and all nine are merged to `main`
  (confirmed by `git log --oneline main`: merge commits `fa53591`, `37d1fb9`, `d5cd9a3`,
  `22be59d`, `a160841`, `899757d`, `a4d4fd5`, `56f7102`, `036f54d`).
- The working tree is on `main`, clean, HEAD at `56f7102` (the 194 merge).
- The suite is already green: 1557 runs, 5318 assertions, 0 failures. This plan does not
  re-run it (no test work is planned here); `bin/test` is the project's verify command
  (`ruby bin/test`) if the executor wants an independent check before publishing.
- The doctor's live result is 1 fail (`hooks_match_registry`, expected: the new
  `plastic-links-gate` hook has not reached `~/.claude/hooks` yet, which this release plus a
  local update resolves) and 2 warn (`graph_links_projection`, `signals_complete`, both out of
  this release's scope per spec D5/D6). This release proceeds without waiting on either warning.

## Task 1: Cut and publish the 1.4.0 release

**Files:**
- Modify: `package.json:3` (version)
- Modify: `.claude-plugin/plugin.json:4` (version)
- Modify: `.claude-plugin/marketplace.json:8` (nested `plugins[0].version`)
- Modify: `CHANGELOG.md` (new bullet under `## Released`)
- Create (temp, not committed): `/tmp/plastic-release-v1.4.0-tag-message.txt`

The full ordered steps, exact commands, and exact text for this task are written once, in full,
in `actions/ACTION_1.md` (the tier is S, so the whole delivery is one consolidated action file;
nothing here duplicates it beyond this map).

- [ ] Step 1: Confirm starting state (branch, clean tree, current versions) - see ACTION_1 Step 1
- [ ] Step 2: Bump `package.json`, `plugin.json`, `marketplace.json` to 1.4.0 - ACTION_1 Step 2
- [ ] Step 3: Run `ReleaseGuard.check` to confirm the three files agree and carry no
      pre-release suffix - ACTION_1 Step 3
- [ ] Step 4: Add the 1.4.0 entry to `CHANGELOG.md` under `## Released` - ACTION_1 Step 4
- [ ] Step 5: Commit the version bump and changelog together - ACTION_1 Step 5
- [ ] Step 6: Create the annotated tag `v1.4.0` - ACTION_1 Step 6
- [ ] Step 7: Push the commit and the tag - ACTION_1 Step 7
- [ ] Step 8: Create the GitHub release with `--latest` - ACTION_1 Step 8
- [ ] Step 9: `npm publish` to the `latest` dist-tag - ACTION_1 Step 9
- [ ] Step 10: Verify npm, GitHub, and the git tag all agree on 1.4.0 - ACTION_1 Step 10

## Task 2: Close the roadmap, record the outcome, complete intent 195

**Files:**
- Modify: `~/.plastic/projects/plastic/roadmaps/doctor-consistency.md` (line 89 checkbox, append
  one `## Log` entry; `## Goal` untouched)
- Write: `store/195--roadmap-doctor-consistency/outcome.md` (real content, replaces the
  scaffold placeholder)
- Git worktree operations (merge-then-remove, no-op merge) + `scripts/end-intent`

Runs after Task 1 (`ACTION_1.md`) is fully done: v1.4.0 published and verified on npm/GitHub/git.
The full ordered steps, exact commands, and exact text for this task are written once, in full,
in `actions/ACTION_2.md`.

- [ ] Step 1: Re-confirm the nine collected intents' delivery (read-only) - ACTION_2 Step 1
- [ ] Step 2: Sync the local install (`npx @zalom/plastic update`) and re-run the doctor;
      confirm `hooks_match_registry` clears to pass while the two other warnings persist -
      ACTION_2 Step 2
- [ ] Step 3: Correct the 194 checkbox and append the closing Log entry (true partial result,
      `## Goal` untouched) - ACTION_2 Step 3
- [ ] Step 4: Write intent 195's real `outcome.md` (nine-intent confirmation, doctor
      before/after, the two mechanism-level lessons, the open dealintell item) - ACTION_2 Step 4
- [ ] Step 5: Worktree cleanup (merge-then-remove, no-op merge since no code work happened
      there) - ACTION_2 Step 5
- [ ] Step 6: Complete intent 195 via `scripts/end-intent --disposition delivered` - ACTION_2
      Step 6

The dealintell Links repair (global 26, dealintell 3b, dealintell 15) stays an open item pending
the owner's one-time grant. It is never executed by either action; it is recorded, visibly, in
the checklist and in outcome.md's Follow-ups. Proposal at intent 192's
`resources/repair-proposal--dealintell-3b-15.md`.

## Notes

- Version bump is minor (1.3.0 -> 1.4.0), not patch: the batch ships new user-facing surface
  (the `plastic-links-gate` hook, the `config_asks.yml` manifest, `validate-project`,
  `restore-intent-v1`) with no breaking change to any existing command (spec Approach,
  Alternatives Considered).
- `~/.plastic/projects/plastic/project.yml`'s `release:` section is the source of truth this
  plan follows: `verify: "ruby bin/test"`, `version_files:` the three files above,
  `tag_format: "v{{version}}"`, `on_green: [github_release, npm_publish]`.
- No PRs on this project (owner ruling: personal/solo project, merge straight to main). All nine
  intents already merged directly; this release branches from nothing and needs no merge step.
- No em dash anywhere in the tag name, the commit messages, the release title, or any store
  edit (standing owner rule). Verified by inspection in ACTION_1's and ACTION_2's exact text.
- Task 2 does not run until Task 1 is fully verified done (npm/GitHub/git all agree on 1.4.0):
  the doctor re-check, the roadmap's closing Log entry, and outcome.md's "before/after" claim
  all depend on the release actually having shipped first.
- Intent 195 has its own provisioned code worktree and paired store worktree, both at the exact
  same commit as `main` (zero diff, no code work ever happened there, matching spec.md's
  Non-Goals). Task 2 Step 5 still runs the standard merge-then-remove cleanup rather than
  skipping it, even though the merge is a no-op here.
- `scripts/end-intent` refuses to run against the scaffold `outcome.md` placeholder or a
  `disposition:` mismatch, so Task 2 Step 4 (write outcome.md) must land before Step 6
  (`end-intent`).
