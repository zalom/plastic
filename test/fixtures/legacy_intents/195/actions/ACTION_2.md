# Action 2: Close the roadmap, record the outcome, complete intent 195

You need no other context to run this. Everything you need is below.

## What this is

`actions/ACTION_1.md` cuts and publishes release `v1.4.0` (version bump, CHANGELOG, tag, push,
GitHub release, npm publish, three-surface verify). This action runs AFTER `ACTION_1.md` is
fully done (v1.4.0 published and verified on npm/GitHub/git). It does the rest of intent 195's
scope: confirms the doctor's fail actually clears once the new hook is locally installed, closes
the `doctor-consistency` roadmap honestly (not a false clean pass), writes intent 195's real
`outcome.md`, and completes the intent. You do NOT touch the three version files, `CHANGELOG.md`,
or any release/tag/publish command; that is `ACTION_1.md`'s job and is already done by the time
you start.

No em dash anywhere you write. Use a hyphen or restructure the sentence.

## Precondition: confirm ACTION_1 landed

```bash
cd /Users/zlatko/apps/personal/plastic
npm view @zalom/plastic dist-tags
gh release list --limit 1
git ls-remote --tags origin | grep v1.4.0
```

Expected: `dist-tags` shows `latest: 1.4.0`; the top release line is `v1.4.0` with `Latest`;
the tag line is present. If any of these is missing, `ACTION_1.md` has not finished. Stop and
report, do not proceed or improvise the release steps yourself.

## Step 1: Re-confirm the nine collected intents are genuinely delivered

Read-only, from the store, not the roadmap's own claim (this batch is specifically about tools
that report success falsely, so its own closing intent does not skip this check):

```bash
for id in 187 188 189 190 191 192 193 194 196; do
  dir=$(find ~/.plastic/projects/plastic/store -maxdepth 1 -type d -name "${id}--*")
  echo -n "$id: "
  grep -m1 "disposition:" "$dir/outcome.md"
done
```

Expected: nine lines, each `disposition: delivered`. If any intent shows anything else, stop and
report before continuing; do not write outcome.md or close the roadmap on an unconfirmed claim.

## Step 2: Sync the local install and confirm the doctor's fail actually clears

First, the baseline (still true even after ACTION_1's publish, because `npm publish` never
touches a local `~/.claude/hooks` install; only `plastic update` does):

```bash
cd /Users/zlatko/apps/personal/plastic
ruby scripts/doctor.rb > /tmp/doctor-before-195.json
ruby -rjson -e 'd = JSON.parse(File.read("/tmp/doctor-before-195.json"));
puts d["status"]; puts d["summary"];
d["checks"].reject { |c| c["status"] == "pass" }.each { |c| puts "#{c["status"]} #{c["category"]} #{c["name"]}: #{c["message"]}" }'
```

Expected: `status` is `fail`; the non-pass lines are exactly:

```
fail agent_registration hooks_match_registry: 1 hook registration(s) diverge from HookRegistry
warn conventions graph_links_projection: 3 graph_links_projection violation(s)
warn done_signals signals_complete: 44 terminal completeness gaps (outcome.md or the savepoint Done echo is missing; advisory on immutable history)
```

(Confirmed by this action's author with this exact command and this exact output before the
release; re-running it here proves it is still true right up to the moment of the fix, not
stale.)

Now sync the local install to the version ACTION_1 just published:

```bash
npx @zalom/plastic update
```

Expected: it resolves to `1.4.0`, re-installs (`install --reinstall --ledger-action update
--claude` under the hood), and this is the step that actually writes
`~/.claude/hooks/plastic-links-gate` and merges it into `settings.json` (`npm publish` alone
never does this; `InstallerCore#merge_claude_hooks` only runs on install/update). Any "Config
question(s) introduced by this update" block printed here is unrelated to this intent; relay it
to the user per the update skill if one appears, but do not let it block this action.

Re-run the doctor:

```bash
ruby scripts/doctor.rb > /tmp/doctor-after-195.json
ruby -rjson -e 'd = JSON.parse(File.read("/tmp/doctor-after-195.json"));
puts d["status"]; puts d["summary"];
d["checks"].reject { |c| c["status"] == "pass" }.each { |c| puts "#{c["status"]} #{c["category"]} #{c["name"]}: #{c["message"]}" }'
```

Expected: `status` is now `warn` (not `fail`, not `pass`). The non-pass lines are now exactly:

```
warn conventions graph_links_projection: 3 graph_links_projection violation(s)
warn done_signals signals_complete: 44 terminal completeness gaps (outcome.md or the savepoint Done echo is missing; advisory on immutable history)
```

`hooks_match_registry` must be absent from this list (i.e. now `pass`). If it still fails, stop:
either `npx @zalom/plastic update` did not actually resolve to `1.4.0` yet (npm propagation
delay - wait a minute and retry `npm view @zalom/plastic dist-tags` first), or something is
wrong with the hook registration; do not edit the roadmap or write outcome.md claiming a clean
hook fix until this genuinely reads `pass`.

## Step 3: Confirm the roadmap close (ALREADY DONE, do not re-apply)

File: `~/.plastic/projects/plastic/roadmaps/doctor-consistency.md`.

STOP: both roadmap edits already landed during the How stage, before this action file was
written. This step is CONFIRM-ONLY. Do NOT re-apply them. An earlier draft of this action told
you to make the edits; that draft was written against a stale view of the file. Re-applying
Edit B in particular would append a SECOND closing Log entry and leave the roadmap claiming its
own close twice.

Confirm both, read-only:

```bash
R=~/.plastic/projects/plastic/roadmaps/doctor-consistency.md
grep -c '^- \[x\] 194 .* - delivered$' "$R"     # expect 1
grep -c '^- \[ \] 194 .* - delivering$' "$R"    # expect 0
grep -c '^- 2026-07-14 .* UTC - ' "$R"          # expect exactly 1, NOT 2
```

Expected: `1`, `0`, `1`. That is the finished state.

- If the third command prints `2` or more, a duplicate closing Log entry was written. Remove the
  extra one so exactly one remains, then continue.
- If the first prints `0` and the second prints `1`, the checkbox edit was somehow reverted;
  change that line to `- [x] ... - delivered` (194's own `outcome.md` reads
  `disposition: delivered`; the roadmap line was simply stale) and re-run the checks.

**Do not touch `## Goal`.** Rewriting the charter to match the result is retconning (spec.md
Approach); the truth of what actually shipped belongs in the Log entry and in intent 195's own
`outcome.md`, not in a rewritten Goal section. `## Goal` must stay byte-for-byte as it is.

One caveat for Step 4 below. The Log entry already on disk was written BEFORE the release, so it
states the release as the decision, not as an accomplished fact, and it records
`hooks_match_registry` as still failing. That was correct when written. After Step 2 you will
have observed whether the check actually cleared. If it did, append nothing new here: the Log
records the decision and `outcome.md` (Step 4) carries the verified result. The roadmap Log and
outcome.md are allowed to differ in tense; they are not allowed to differ in fact.

This file lives in the `~/.plastic` store repo (a separate, local-only git repo from the plastic
code repo), which auto-commits at the standard checkpoints; do not `git commit` it by hand here.
It is swept into the commit `scripts/end-intent` makes in Step 6 below.

## Step 4: Write intent 195's own outcome.md

File: `~/.plastic/projects/plastic/store/195--roadmap-doctor-consistency/outcome.md`. This
REPLACES the current scaffold placeholder entirely (its first line is the sentinel
`<!-- plastic:placeholder -->`; `scripts/end-intent` in Step 6 refuses to run against that
sentinel or against a `disposition:` that does not match `--disposition delivered`, so this must
be real content, not the template, before Step 6).

READ THIS BEFORE YOU PASTE. The text below is a DRAFT written before the release ran. It asserts
that `hooks_match_registry` cleared to pass. That is a PREDICTION, not an observation. You are
closing a batch whose entire subject is tools and documents that report a success nobody
verified. Do not become one.

So: write what Step 2 actually printed, not what this draft predicts. If the doctor's post-update
run showed `hooks_match_registry` still failing, or a different warning count, or anything else
that does not match, then CHANGE THE TEXT BELOW to say what really happened and note why. An
`outcome.md` that disagrees with the doctor is worse than no `outcome.md`. If Step 2 matched the
prediction exactly, this draft is accurate and you can use it as written.

Content (adjust to the observed result; the `<TAG-DATE>` line matches whatever real date
`ACTION_1.md`'s CHANGELOG entry used, so check `CHANGELOG.md`'s new top bullet and use the same
string):

```markdown
---
disposition: delivered
---
# Outcome: Roadmap: the doctor-consistency batch - decision and release cut

## Summary

Intent 195 owned this batch's decision and release cut, not its delivery. All nine collected
intents (187, 188, 189, 190, 191, 192, 193, 194, 196) were independently verified delivered
against their own `outcome.md` files, not the roadmap's own claim or their plans, because a
batch about tools that report success falsely cannot let its own closing intent skip that check
(one real inconsistency surfaced this way: the roadmap's Batch 4 checkbox for 194 was still
unchecked and marked "delivering" though 194's own outcome.md already read delivered; corrected
as part of closing the roadmap, not left stale). Release `v1.4.0` was cut and published across
all three version files (`package.json`, `.claude-plugin/plugin.json`,
`.claude-plugin/marketplace.json`), a minor bump (new user-facing surface: the
`plastic-links-gate` hook, the `config_asks.yml` manifest, `validate-project`,
`restore-intent-v1`; no breaking change), tagged `v1.4.0`, and published to npm's `latest`
dist-tag. The doctor's real result was recorded honestly rather than asserted clean: before the
release, 1 fail (`hooks_match_registry`, because the new `plastic-links-gate` hook existed in the
repo and was registered in `HookRegistry` but had not yet reached a local install) and 2 warn
(`graph_links_projection`, `signals_complete`); after the release published and a local
`plastic update` ran, `hooks_match_registry` cleared to pass, exactly as expected (the release
itself was the fix), while the two warnings persist by design (one pending an owner grant that
touches Completed intents, one advisory forever). The `doctor-consistency` roadmap is closed with
that honest partial result recorded in its Log, its Goal section left untouched, and the pending
dealintell Links repair carried forward as an explicit open item, never executed here.

Two mechanism-level lessons are the real yield of this batch and are recorded here because they
are the actual point of the work, not an afterthought:

- **Fix the mechanism, not the list.** Every real fix in this batch worked by removing a
  hardcoded enumeration, not by patching one more entry into it: 190 replaced a per-template
  allowlist test with a glob over `templates/*`; 189 replaced a hardcoded two-store list with a
  shared store-discovery module reading `projects.yml`; 191 replaced a two-name allowlist with a
  four-bucket agent classifier; 196 replaced two private copies of the same heading-parsing logic
  with one shared grouping-heading matcher.
- **Verify a stated fix before trusting it.** In three of the nine intents, the fix named in the
  intent's own brief was the wrong fix, and it was only caught because a team verified the claim
  before building it: 189 found the doctor's own `fix_hint` would have deleted the valid
  `global 26 -> ai-agents-resources:1` link, because unknown-store and genuinely-dead both
  classified as `:dead`, and `:dead` means delete; 191's team overruled a coordinator steer with
  evidence, because no `~/.plastic/agents` tree exists at doctor run time, so the originally
  suggested fix would have silently passed in the field; 192 found the intent's own premise was
  half wrong - PLASTIC.md forbids both hand-writing a Links line and auto-deleting one, and
  `project-links` was itself violating the second half, so the doctor's `fix_hint` would have
  destroyed dealintell 15's only record of a real relationship.

## Delivered

- Verified all nine collected intents (187, 188, 189, 190, 191, 192, 193, 194, 196) show
  `disposition: delivered` in their own outcome.md (command and output in Verification below).
- Release `v1.4.0` cut and published: three version files bumped in lockstep and guarded by
  `ReleaseGuard.check` (stable, no mismatches, no pre-release suffix), one intent-centric
  CHANGELOG.md bullet, annotated tag `v1.4.0`, GitHub release with the `Latest` badge, npm
  publish to the `latest` dist-tag. Full command sequence and exact expected output for this
  piece are in `actions/ACTION_1.md`.
- Ran the doctor live before the release (still fail: `hooks_match_registry`, warn:
  `graph_links_projection` + `signals_complete`) and again after a local `plastic update` synced
  the newly-published hook (`hooks_match_registry` cleared to pass; the two warnings persisted,
  as expected).
- Corrected `doctor-consistency.md`'s Batch 4 checkbox for 194 from unchecked "- delivering" to
  checked "- delivered"; appended one closing Log entry recording the true partial result; left
  `## Goal` untouched; roadmap marked closed.
- Left the dealintell Links repair (global 26, dealintell 3b, dealintell 15) unexecuted; see
  Follow-ups.

## Verification

- AC1 (nine intents confirmed delivered) - `grep -m1 "disposition:" <each store>/outcome.md` for
  187, 188, 189, 190, 191, 192, 193, 194, 196 -> all nine read `disposition: delivered`.
- AC2 (doctor's real result recorded) - `ruby scripts/doctor.rb` from the repo, before the
  release -> `status: fail`, non-pass checks exactly `hooks_match_registry` (fail),
  `graph_links_projection` (warn), `signals_complete` (warn), matching spec.md's claimed result
  exactly. After the release plus `npx @zalom/plastic update` -> `status: warn`,
  `hooks_match_registry` now pass, the same two warnings unchanged.
- AC3 (version bumped, tagged, published) - `npm view @zalom/plastic dist-tags` shows
  `latest: 1.4.0`; `gh release list --limit 1` shows `v1.4.0` with `Latest`; `git ls-remote --tags
  origin | grep v1.4.0` shows the tag on the remote. (Full detail in ACTION_1.md's own Step 10.)
- AC4 (roadmap corrected and closed) - re-read `doctor-consistency.md` after Step 3 above: line
  89 now `[x] ... - delivered`; the closing Log entry is the file's last line; `## Goal` is
  byte-identical to its pre-195 text.
- AC5 (dealintell repair not executed) - no edit touched `store/192.../resources/repair-proposal`
  or any of the three named Completed intents (global 26, dealintell 3b, dealintell 15); the item
  is carried below as an explicit Follow-up, not silently dropped.
- AC6 (two lessons recorded) - see Summary above, naming which intents demonstrated each.
- AC7 (195 reaches Completed) - this outcome.md plus `scripts/end-intent --disposition delivered`
  (Step 6 below), which moves the INDEX.md line to `## Completed` and clears `delivery.lock`.

## Follow-ups

- **Dealintell Links repair - OPEN, owner grant pending.** `graph_links_projection` warns on 3
  cases (global 26, dealintell 3b, dealintell 15) that need a store repair touching Completed
  intents. The proposal is written and held at intent 192's
  `resources/repair-proposal--dealintell-3b-15.md`: drop dealintell 3b's three broken
  single-dash wikilinks, add the missing frontmatter edge `3a.chain += ["15"]` for the one real
  relationship, reproject global 26. It requires the owner's explicit one-time grant under the
  completed-intents-immutable rule before it can run. Until granted, this stays open and
  `graph_links_projection` stays at warn.
- `signals_complete`'s 44 gaps (41 legacy, permanently advisory by design; 3 pre-convention, out
  of this batch's scope) are not this intent's or any single future intent's job to close; noted
  here only so the number is not mistaken for a regression by a future doctor run.
- The follow-ups each of the nine collected intents recorded in their own outcome.md (Enola
  reindex-at-close automation, wiring the safe Links projector into the End tail, folding
  `ProjectValidator` into doctor, narrowing `restore-intent-v1`'s Links reproject to one intent,
  correcting PLASTIC.md's `chain` bullet direction, and others) belong to future intents, not
  this release decision (spec.md Non-Goals).
```

## Step 5: Worktree cleanup (merge-then-remove)

Intent 195 has a provisioned code worktree (branch `plastic/195--roadmap-doctor-consistency` in
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/195--roadmap-doctor-consistency`) and a
paired store worktree, both still at the exact same commit as `main` (zero diff: no code work
was ever done there, matching spec.md's Non-Goals - this intent's only code-repo changes are the
release-cut commit ACTION_1 already made directly on `main`). Merge-then-remove both, standard
procedure, never skipped even when the merge is a no-op:

```bash
cd /Users/zlatko/apps/personal/plastic
ruby -r ~/.plastic/scripts/lib/worktree -r ~/.plastic/scripts/lib/bridge -e \
  'b = Bridge.discover_bridge(session: ENV["CLAUDE_CODE_SESSION_ID"], cwd: Dir.pwd); Worktree.finish(b, merge: true) if b'
```

Expected: both worktrees (code + paired store) are removed, both repos pruned, the worktree
block cleared from the bridge. Since the branch is already an ancestor of (or identical to)
`main`, the merge itself is a harmless no-op ("Already up to date" or equivalent); this is
expected, not an error. If `git worktree list` afterward still shows a
`195--roadmap-doctor-consistency` entry in either repo, run `git worktree prune` in that repo.

## Step 6: Complete intent 195

Requires Step 4's real `outcome.md` to already exist (the guard below refuses on the scaffold
placeholder or a disposition mismatch):

```bash
ruby ~/.plastic/scripts/end-intent --store ~/.plastic/projects/plastic/store --id 195 \
  --disposition delivered \
  --session "$CLAUDE_CODE_SESSION_ID" \
  --outcome-summary "delivered in v1.4.0: doctor-consistency roadmap closed, nine intents (187-194, 196) confirmed delivered against their own outcome.md, doctor honestly recorded (1 fail before the release, cleared by the release's own update; 2 warn remain, one pending an owner grant, one advisory by design)" \
  --index-note "v1.4.0, roadmap cut; closes doctor-consistency batch (187-194, 196); doctor cleared hooks_match_registry post-release, graph_links_projection and signals_complete remain (owner grant pending, advisory legacy); suite 1557 runs, 5318 assertions, 0 failures"
```

Expected: exit `0`. This stamps intent 195's own `## Outcome` section, moves its `INDEX.md` line
from `## Active` to `## Completed`, appends the savepoint `Done` bookend, commits the store
repo (sweeping in Step 3's roadmap edit and Step 4's outcome.md together), and clears
`delivery.lock`.

A non-zero exit needs attention, not improvisation: `4` means a live foreign session holds the
lock (back off, do not force it); `5` means the code worktree is still dirty (should not happen,
Step 5 already removed it - investigate before ever passing
`--discard-worktree-changes`); `3` means steps 1-4 committed but the lock genuinely would not
clear (run `/plastic-doctor` and check the lock status); `2` means the outcome.md guard refused
(re-check Step 4 was written correctly, not left as the placeholder, `disposition:` reads exactly
`delivered`).

## What "done" looks like

- `hooks_match_registry` reads `pass` in a live doctor run against `~/.plastic` (proof the
  release actually fixed what it claimed to fix).
- `doctor-consistency.md` line 89 (or wherever the 194 entry now sits) reads
  `- [x] 194 ... - delivered`; the file's last line is the new closing Log entry; `## Goal` is
  untouched.
- `store/195--roadmap-doctor-consistency/outcome.md` is real content (not the scaffold), records
  the nine-intent confirmation, the doctor before/after, the two lessons, and the open dealintell
  item.
- Both of intent 195's worktrees (code + paired store) are gone; `git worktree list` in
  `/Users/zlatko/apps/personal/plastic` shows only the main checkout.
- `~/.plastic/projects/plastic/INDEX.md` lists 195 under `## Completed`, not `## Active`;
  `delivery.lock` no longer exists for this intent.

## What is explicitly NOT part of this action

- No version bump, no CHANGELOG edit, no tag, no push, no `gh release`, no `npm publish`. All of
  that is `actions/ACTION_1.md`, already done before this action starts.
- No execution of the dealintell Links repair (global 26, dealintell 3b, dealintell 15). It stays
  an open item pending the owner's one-time grant; recorded in outcome.md's Follow-ups, never
  run.
- No edit to `## Goal` in `doctor-consistency.md`. Only the Batch 4 checkbox and the closing Log
  entry.
- No code change, no test run. The suite was already confirmed green (1557 runs, 5318 assertions,
  0 failures) before this plan was written.
