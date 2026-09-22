# Action 1: Cut and publish the 1.4.0 release for the doctor-consistency batch

You need no other context to run this. Everything you need is below.

## What this is

Nine intents (187, 188, 189, 190, 191, 192, 193, 194, 196) are already delivered and already
merged to `main` in `/Users/zlatko/apps/personal/plastic`. The suite is already green: 1557
runs, 5318 assertions, 0 failures. Your only job is the release cut: bump the version, write one
CHANGELOG entry, tag, push, publish, and verify. You do NOT write code, you do NOT run or fix
tests, you do NOT edit the roadmap file, and you do NOT touch the dealintell Links repair.

No em dash anywhere you write: not in the tag name, not in any commit message, not in the
release title. Use a hyphen or restructure the sentence.

Work inside `/Users/zlatko/apps/personal/plastic`. All commands below assume that as `cwd`.

## Step 1: Confirm starting state

```bash
cd /Users/zlatko/apps/personal/plastic
git status --short
git branch --show-current
git log -1 --format="%H %s"
```

Expected: `git status --short` prints nothing (clean tree). `git branch --show-current` prints
`main`. The log line's subject is the 194 merge (`merge: 194 a release announces its own config
question from the new code`) or later. If any of this differs, stop and report before
proceeding, do not improvise a fix.

```bash
grep '"version"' package.json .claude-plugin/plugin.json
grep -A1 '"plugins"' .claude-plugin/marketplace.json | grep '"version"\|"name"'
```

Expected: all three read `1.3.0`.

## Step 2: Bump the three version files to 1.4.0

**`package.json`** (top-level `version` key, line 3):

Old:
```json
  "version": "1.3.0",
```
New:
```json
  "version": "1.4.0",
```

**`.claude-plugin/plugin.json`** (top-level `version` key, line 4):

Old:
```json
  "version": "1.3.0",
```
New:
```json
  "version": "1.4.0",
```

**`.claude-plugin/marketplace.json`** (nested inside the `plugins` array, the `plastic` plugin
entry's own `version` key, NOT a top-level key):

Old:
```json
      "name": "plastic",
      "description": "Intent-driven state management for AI coding sessions",
      "version": "1.3.0",
```
New:
```json
      "name": "plastic",
      "description": "Intent-driven state management for AI coding sessions",
      "version": "1.4.0",
```

Make each edit with an exact string replacement (old text above → new text above), one file at
a time. Do not reformat or reorder anything else in these files.

## Step 3: Confirm the three files agree (release guard)

```bash
ruby -e '
require "./scripts/lib/release_guard"
result = ReleaseGuard.check(
  package_json: "package.json",
  plugin_json: ".claude-plugin/plugin.json",
  marketplace_json: ".claude-plugin/marketplace.json",
  stable: true
)
puts result.inspect
raise "release guard failed" unless result.ok?
'
```

Expected: `#<struct ReleaseGuard::Result ok=true, version="1.4.0", mismatches=[],
prerelease_suffix=nil>` and no exception raised. If `ok` is false, stop: one of the three files
was not edited correctly. Re-check Step 2 before continuing.

## Step 4: Add the CHANGELOG.md entry

Open `CHANGELOG.md`. Find this exact spot near the top:

```markdown
## Unreleased

## Released

- `1.3.0` - shipped 2026-07-13; the advisor (intent 185): ...
```

Insert one new bullet immediately after the `## Released` line, immediately before the existing
`1.3.0` bullet (newest-first, matching every prior entry). The new bullet, verbatim:

```markdown
- `1.4.0` - shipped 2026-07-14; closes the doctor-consistency roadmap (intent 195): 196 (the roadmap queue reader and savepoint now accept the current `## Batches` heading, not only the legacy `## Waves` one, so a roadmap written after the batches rename stops parsing as empty and reporting no work), 187 (the plastic repo is indexed with Enola so code work can resolve a symbol directly instead of a blind grep, with a worktree-copy leak and a test-file exclusion bug both fixed before the rest of the batch built on it), 188 (closing an intent now always drops its delivery lock and moves it out of the active list for real, whether its INDEX line uses an em dash or a plain hyphen), 189 (the graph repair tools now read the real list of registered stores instead of a hardcoded pair, so a link into a store they used to be blind to is never again read as dead and deleted), 190 (every file under `templates/` now reaches a fresh install by derivation instead of a hand-kept list, and spawning a project verifies its own files were actually written instead of printing OK on a silent no-op), 191 (the doctor's model-drift check recognizes the two consultation advisor agents shipped in 1.3.0 and stops flagging them as unsanctioned drift), 192 (a new hook blocks a Write or Edit that would leave an intent's `## Links` section out of step with its own frontmatter, and the Links projector now keeps a line it cannot explain instead of deleting it), 193 (restoring an intent to its first delivered version now reverts only the narrative text; the frontmatter links other intents wrote back to it afterward are preserved, never dropped), and 194 (a release can now announce a new configuration question it introduces through a small manifest file, so `update` and `doctor` tell the user what changed instead of leaving it silent); minor bump, not patch, because the batch ships new user-facing surface (the links-gate hook, `restore-intent-v1`, `validate-project`, the config-asks manifest) with no breaking change to any existing command; suite green at 1557 runs.
```

Leave everything else in `CHANGELOG.md` untouched.

## Step 5: Commit the version bump and changelog together

```bash
cd /Users/zlatko/apps/personal/plastic
git add package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump version to 1.4.0 - doctor-consistency batch release cut"
```

Expected: one new commit on `main`, containing exactly these four files.

## Step 6: Create the annotated tag v1.4.0

First, regenerate the commit-level bullet list since the last tag, to build the tag message body:

```bash
git log v1.3.0..HEAD --oneline --no-merges | grep -E "^[a-f0-9]+ (feat|fix|refactor):"
```

Write the tag message to a temp file (use the Write tool, or `cat >` if working from a plain
shell) at `/tmp/plastic-release-v1.4.0-tag-message.txt`. First line is `<tag> - <short name>`,
then a blank line, then one bullet per line from the command above, each rewritten as
`- <type>: <subject>` (drop the commit hash). Content:

```
v1.4.0 - the doctor-consistency batch

- fix: restore-intent-v1 never loses a prose sibling or a resolved edge
- fix: remove checklist.md mistakenly committed to the code repo root
- fix: close spec.md acceptance-criteria gaps in reporting and revisions.md entries
- fix: register restore-intent-v1 script and lib in the install manifest
- feat: add restore-intent-v1 CLI shell
- feat: add RestoreIntentV1 pure graph math (union + target resolution)
- fix: teach doctor's agent_model_drift about consultation agents
- fix: close a TOCTOU in end-intent's direct-lock-release fallback
- fix: make the CLI missing-template test a real subprocess smoke test
- fix: harden end-intent's disarm/lock guards against 3 reproduced failure modes
- fix: ship every template on install, add a project-spawn self-check
- feat: mechanize the end-tail disarm in scripts/end-intent (intent 188)
- fix: align doctor store_index seeding and split dead/unknown_store audit messages
- fix: graph tools discover every store instead of a hardcoded three
- fix: index Plastic's tests and match Enola's real default ignore globs
- fix: exclude worktree copies from the Enola snapshot
- fix: roadmap tooling reads Batches as canonical, Waves as legacy
- feat: register Enola for the plastic repo and add an Enola-first power-tools branch
```

If the command in this step prints a different list than the one above (more or fewer lines),
use what the command actually prints, not the list above; the list above is what it printed
when this plan was written and should still match, but the command is the source of truth.

Then create the annotated tag from that file:

```bash
git tag -a v1.4.0 -F /tmp/plastic-release-v1.4.0-tag-message.txt
git tag -l -n1 v1.4.0
```

Expected: the second command prints `v1.4.0          v1.4.0 - the doctor-consistency batch`.
Do NOT use `git tag -a v1.4.0 -m "..."` with the message inline in a `$(...)` heredoc
construction; use `-F` against the file written above.

## Step 7: Push the commit and the tag

```bash
git push origin main --tags
```

Expected: `main` advances on the remote by one commit, and `v1.4.0` appears in the remote tag
list. Confirm:

```bash
git ls-remote --tags origin | grep v1.4.0
```

Expected: at least one line naming `refs/tags/v1.4.0` (an annotated tag prints both
`refs/tags/v1.4.0` and `refs/tags/v1.4.0^{}`).

## Step 8: Create the GitHub release

```bash
gh release create v1.4.0 \
  --title "v1.4.0 - the doctor-consistency batch" \
  --latest \
  --generate-notes \
  --notes-start-tag v1.3.0
```

`--latest` is required: it is what puts the "Latest" badge on this release instead of leaving
it on `v1.3.0`. Expected: command prints the new release URL
(`https://github.com/zalom/plastic/releases/tag/v1.4.0`).

## Step 9: Publish to npm on the latest dist-tag

```bash
npm publish --access public
```

No `--tag` flag: this repo is stable (no pre-release suffix in `package.json`'s version), so
the default `latest` dist-tag is exactly what the roadmap's own header ("Ships stable") calls
for. Expected: npm prints `+ @zalom/plastic@1.4.0`.

## Step 10: Verify all three surfaces agree

Run all three:

```bash
npm dist-tag ls @zalom/plastic
gh release list --limit 3
git tag -l -n1 v1.4.0
```

Expected, read together:
- `npm dist-tag ls @zalom/plastic` includes the line `latest: 1.4.0` (the `alpha` and `beta`
  lines are unrelated and unchanged).
- `gh release list --limit 3` shows `v1.4.0` on its top line with `Latest` in the status column,
  and `v1.3.0` on the line below it with no status (the badge moved off it).
- `git tag -l -n1 v1.4.0` shows the tag exists locally with the message from Step 6.

If the GitHub "Latest" badge did not land on `v1.4.0` (a known occasional drift), fix it without
re-releasing:

```bash
gh release edit v1.4.0 --latest
```

## What "done" looks like

- `package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` all read
  `1.4.0`.
- `CHANGELOG.md` has the new `1.4.0` bullet as the first line under `## Released`.
- One version-bump commit and one annotated tag `v1.4.0` exist on `main`, both pushed to
  `origin`.
- `npm dist-tag ls @zalom/plastic` reports `latest: 1.4.0`.
- `gh release list` shows `v1.4.0` carrying the `Latest` badge.
- `git ls-remote --tags origin` shows `v1.4.0` on the remote.

## What is explicitly NOT part of this action

- No edit to `roadmaps/doctor-consistency.md` (the 194 checkbox and the closing Log entry are
  written by a different agent in this session; this action only cuts the release).
- No execution of the dealintell Links repair (global 26, dealintell 3b, dealintell 15). It
  stays an open item pending the owner's one-time grant; do not touch it here.
- No edit to intent 195's own `outcome.md`, `INDEX.md` entry, or savepoint. Completing intent
  195 is a separate step the coordinator runs after this release cut lands, not part of this
  action.
- No code change and no test run. The suite was already confirmed green (1557 runs, 5318
  assertions, 0 failures) before this plan was written.
