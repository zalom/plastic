---
name: plastic-releasing
description: Use when merging a feature branch to main and tagging a release, bumping the version, or when the user says "release", "tag", or "ship it"
user-invocable: true
---

# Releasing

Merge, bump, tag, push. Annotated tags with changelogs. Semantic versioning.
Project configuration drives the workflow - no hardcoded assumptions.

## Checklist

- [ ] Read project config
- [ ] All tests pass (or verification skipped per config)
- [ ] Merge feature branch to main
- [ ] Bump version in configured version files
- [ ] Stable-cut guard passes (version files agree, no pre-release suffix; stable/latest cuts only)
- [ ] Commit version bump
- [ ] Create annotated tag
- [ ] Push to remote with tags
- [ ] Run post-push actions (GitHub release, npm publish, etc.)
- [ ] Verify release sync (npm dist-tag, GitHub "Latest", git tag all show the new version)
- [ ] Clean up the intent's worktrees (merge-then-remove)
- [ ] Complete active intent

## Workflow

### 0. Read Project Config

Before anything else, determine which project we are releasing and load its config.

1. Read `~/.plastic/projects.yml` - find the project whose `path` matches the current working directory.
2. Extract the project slug (the key under `projects:`).
3. Read `~/.plastic/projects/{slug}/project.yml` - this contains the `release:` section.

Expected `release:` keys in project.yml:

```yaml
release:
  verify: "bin/rails test"              # command to run before release
  version_file: package.json            # single file containing the version
  version_files:                        # multiple files (overrides version_file)
    - package.json                      # list EVERY file carrying the version;
    - .claude-plugin/plugin.json        # they must all be bumped together or they drift
    - .claude-plugin/marketplace.json
  tag_format: "v{{version}}"            # tag naming pattern ({{version}} is replaced)
  on_green:                             # actions to run after push succeeds
    - github_release
    - npm_publish
  on_complete: commit_and_push          # what to do with the version bump commit
  on_red: stop                          # what to do if verification fails
```

**Fallback:** If no project.yml exists or it has no `release:` section, fall back to asking the user for each step - verify command, version files, tag format, and post-push actions.

### 1. Verify Tests Pass

Run the verification command from `release.verify` in project.yml:

```bash
# Example: release.verify = "ruby -Itest test/*_test.rb"
<verify-command-from-config>
```

- If `release.verify` is present: run it. All checks must pass before proceeding.
- If `release.verify` is absent or empty: skip verification. Log that no verify command is configured.
- If `release.on_red` is `stop`: abort the release on failure.
- If `release.on_red` is `fix_and_retry`: ask the user to fix and re-run.

### 2. Determine Version Bump

| Change type | Bump | Example |
|-------------|------|---------|
| Breaking changes | Major | 0.x.0 → 1.0.0 |
| New features | Minor | 0.3.0 → 0.4.0 |
| Bug fixes only | Patch | 0.4.0 → 0.4.1 |

Pre-1.0: minor bumps for features, patch for fixes. No major until stable.

### 3. Merge Feature Branch

```bash
git checkout main
git merge <branch-name> --no-ff -m "feat: merge intent [ID] - [description]"
```

Always `--no-ff` to preserve branch history in the merge commit.

**Worktree-isolated intents (intent 73c3).** A worktree-delivered intent's code lives on
`plastic/{id}--{slug}`, merged together with cleanup in step 9, not on a hand-made feature
branch. Do not delete the worktree before its branch is merged, or the work is lost. For
the full rationale and the already-merged-by-hand no-op case, read
`references/promotion-and-tagging.md`.

### 4. Bump Version

**Stable-cut guard.** Before touching any version file for a stable (no pre-release suffix,
`latest`) cut, run the guard in `scripts/lib/release_guard.rb`:

```ruby
require "./scripts/lib/release_guard"
result = ReleaseGuard.check(
  package_json: "package.json",
  plugin_json: ".claude-plugin/plugin.json",
  marketplace_json: ".claude-plugin/marketplace.json",
  stable: true
)
raise "release guard failed: #{result.mismatches} #{result.prerelease_suffix}" unless result.ok?
```

If it reports a mismatch or a pre-release-suffix violation, stop and resolve it before bumping
any file. For a beta or alpha cut, pass `stable: false`; only version-file agreement is checked,
a pre-release suffix is expected. Read `references/release-lines.md` for the stable-line
guarantees this guard protects.

Determine which files to update from project.yml:

- If `release.version_files` is set: update ALL listed files (they must stay in sync).
- Else if `release.version_file` is set: update that single file.
- Else: ask the user which files contain the version.

Update the version string in each file, then commit:

**Cut the CHANGELOG entry.** Before committing, edit `CHANGELOG.md` at the repo root so
the changelog change rides this same version-bump commit and reaches the tag. Write one
line in the existing shape:

`` `<version>` - shipped <date>; collected <intent-id> (<one-line summary>) ``

Prepend it as the first bullet under `## Released` (newest-first). If this version was
sitting under `## Unreleased`, move it out of that section and into `## Released`. Keep
the line intent-centric narrative (which intents the cut collected and why), NOT commit
detail: step 5's tag-message changelog and step 7's `gh release create --generate-notes`
already own the commit-level detail, so do not duplicate it here.

```bash
git add <version-files> CHANGELOG.md
git commit -m "chore: bump version to X.Y.Z - [one-line summary]"
```

### 5. Create Annotated Tag

Read `release.tag_format` from project.yml to determine the tag name:

- If set (e.g. `"v{{version}}"`): replace `{{version}}` with the new version string.
- If not set: default to `vX.Y.Z`.

Generate the changelog from commits since the last tag:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline --no-merges | grep -E "^[a-f0-9]+ (feat|fix|refactor):"
```

Create the tag with a multi-line message:

```bash
git tag -a <tag-name> -m "<tag-name> - [release name]

- [changelog bullet points from feat/fix/refactor commits]"
```

### 6. Push

```bash
git push origin main --tags
```

### 7. Post-Push Actions

Read `release.on_green` from project.yml. This is a list of actions to run after a successful push. Execute each in order:

#### `github_release`

Create a GitHub release from the tag:

```bash
gh release create <tag-name> --title "<tag-name> - [release name]" --latest --generate-notes --notes-start-tag <previous-tag>
```

`--latest` is REQUIRED. Pre-release (alpha/beta) tags are NOT auto-promoted to the "Latest"
badge by GitHub, so without it the Releases page keeps showing an older version as Latest while
the newest tag sits below it (a real sync drift we hit on the alpha line). Pass `--latest` on
every release so the newest one always carries the badge. Do NOT pass `--prerelease` unless you
specifically want the release hidden from Latest.

For the first release (no previous tag), write notes manually with `--notes "..."` instead.

#### `npm_publish`

Publish the package to npm with the appropriate dist-tag:

```bash
# Alpha pre-release (version contains -alpha):
npm publish --access public --tag alpha

# Beta pre-release (version contains -beta):
npm publish --access public --tag beta

# Stable release (no pre-release suffix, >= 1.0.0):
npm publish --access public
```

The dist-tag is derived from the version string in `package.json`:
- Contains `-alpha` → `--tag alpha`
- Contains `-beta` → `--tag beta`
- No pre-release suffix → no `--tag` flag (publishes to `latest`)

#### Other values

If `on_green` contains an action not listed above, log it:

```
[releasing] Action "<action>" is configured but not yet implemented. Skipping.
```

If `on_green` is empty or absent: skip post-push actions entirely.

#### Verify sync (always, after the post-push actions)

A release is not done until all three surfaces show the SAME newest version. Confirm:

```bash
npm view <package> dist-tags                      # channel tag (alpha/beta/latest) -> new version
gh release list --limit 1                         # newest release is the new tag AND marked "Latest"
git ls-remote --tags origin | grep <tag-name>     # the tag reached the remote
```

If the GitHub "Latest" badge is on an older tag (the common drift), fix it without re-releasing:

```bash
gh release edit <tag-name> --latest
```

### 8. Clean Up the Intent's Worktrees (merge-then-remove)

This step now runs BEFORE step 9's `end-intent` call (intent 188, D7): `scripts/end-intent`
gained its own step 5 that disarms (releases the worktree, clears `delivery.lock`) as part
of every close. Its plain-remove shape does not merge, so if `end-intent` ran first on a
release, its step 5 would remove the worktree WITHOUT merging the code branch first,
stranding the integrated work (`Worktree.finish` returns early once the worktree block it
needs is gone, per `worktree.rb`'s own "no-op if nothing was provisioned" contract).
Running this merge-then-remove step first means the worktree is already gone by the time
step 9 runs, so `end-intent`'s own disarm becomes a harmless no-op for the worktree
(nothing left to remove), while for the FIRST time on this path it also clears the delivery
lock correctly (G5): before intent 188 this path left the lock stranded, exactly the class
of bug closed by the End-tail enforcement work.

This is the release branch of `plastic-intent-ending`'s Step 5 disarm (`merge: true`), not a
separate concern: a release is the merge-then-remove path for the intent's worktree (intent
73c3), so the intent's code branch is merged back into the default branch BEFORE the worktree
is removed. Drive it through `Worktree.finish` with `merge: true`, which merges the code
branch, then removes the worktree, prunes the repo, and clears the worktree block from the
bridge:

```bash
ruby -r ~/.plastic/scripts/lib/worktree -r ~/.plastic/scripts/lib/bridge -e \
  'b = Bridge.discover_bridge(session: ENV["CLAUDE_CODE_SESSION_ID"], cwd: Dir.pwd); Worktree.finish(b, merge: true) if b'
```

(Uses `discover_bridge`, not a bare session-keyed `Bridge.read`, because a session can own more
than one live bridge now (intent 131) and `discover_bridge` resolves the right one for this cwd.)

Honor the worktree-cleanup rule: never leave an orphaned worktree, and run `git worktree
prune` in the affected repo if you hit a stale reference. For why this is the one place the
merge-vs-remove policy lands on merge, and the fail-open/idempotent guarantees of `finish`,
read `references/promotion-and-tagging.md`.

### 9. Complete Active Intent

A release IS a delivery. The active intent that drove this work must be completed as part of the release process. This is NOT optional. The mechanical close (outcome/INDEX/savepoint/commit, AND disarm since intent 188) is `plastic-intent-ending`'s job, not this skill's: run its backing script rather than restating that prose here.

1. Read `~/.plastic/INDEX.md` (or the project's INDEX.md) - find active intent(s) related to this release.
2. For each active intent being delivered:
   a. Write a real `outcome.md` (never leave the scaffold placeholder), `disposition: delivered`, referencing the release tag.
   b. Update `## Insights` with final observations.
   c. Run the mechanical close (`scripts/end-intent`'s steps 1-5): this stamps the intent file's `## Outcome` summary, moves the INDEX.md line to `## Completed` (dated today, with a rich entry description via `--index-note`), appends the savepoint `Done` bookend, commits the store, and disarms (releases the worktree - already gone from step 8 above - and clears `delivery.lock`), all in one call:
      ```bash
      ruby ~/.plastic/scripts/end-intent --store <store_path> --id <ID> --disposition delivered \
        --session "$CLAUDE_CODE_SESSION_ID" \
        --outcome-summary "delivered in <tag-name>: <one-line summary>" \
        --index-note "<tag-name>, <mode/tier>; <what shipped>; <suite result>"
      ```
      A non-zero exit needs attention: 4 means a live foreign session holds the lock (back
      off), 5 means the code worktree is still dirty (should not happen here, since step 8
      already removed it; investigate before overriding with `--discard-worktree-changes`),
      3 means disarm ran but the lock is still present (run `/plastic-doctor check the lock
      status`).
   d. Update clusters to show `_(completed)_` (the store-curating skill's job on its next pass).

**If no active intent exists for this release**, that itself is a problem - work happened outside the intent system. Log it and move on, but flag it.

## Release lines and channels

Two lanes get code to a release, on top of the workflow above.

- **Default lane.** Branch, merge to main, cut stable, publish to npm `latest`. This is the
  workflow in the steps above, unchanged. Use it for additive, suite-verifiable,
  low-blast-radius work.
- **Beta-verified lane.** Branch, merge to `beta`, publish to the npm `beta` channel, verify in
  real use, then merge to main and cut stable. Use it for work that changes operational
  substrate, or carries data, migration, lock, or state-format risk, or that a hermetic suite
  cannot fully validate on its own.

**Stable-line guarantees.** An external `latest` user can rely on:

- `main` is always green and releasable; no pending revert awaiting re-land sits on `main`.
- A stable release carries no pre-release suffix, publishes to `latest`, and the newest release
  always carries the GitHub "Latest" badge.
- The three version files always agree, checked by `scripts/lib/release_guard.rb` (see Bump
  Version above).
- A stable cut collects only intents that cleared their lane's verification bar.
- Channel semantics are fixed: `latest` is stable, `beta` is the verification line, `alpha` is
  experimental.

Read `references/release-lines.md` for the full lane-routing detail, the version-line map, and
the intent-41 re-land playbook.

## Conventions

- **Annotated tags only** - `git tag -a`, never lightweight tags
- **Tag format** - driven by `release.tag_format` in project.yml (default: `vX.Y.Z`)
- **Tag message** - first line: `<tag> - [short name]`, then blank line, then bullet changelog
- **Commit prefixes** - `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` (conventional commits)
- **Hyphens, never em-dashes** - in tag names, release titles, and commit messages, use a hyphen (`-`). Never an em-dash.
- **Latest badge** - always `gh release create --latest`; the newest release must carry GitHub's "Latest" badge.
- **Version files** - driven by project.yml; list and bump EVERY file carrying the version (they drift otherwise)
- **Verify sync** - after pushing, confirm npm dist-tag, GitHub "Latest", and the git tag all show the new version
- **Branch cleanup** - delete merged feature branches: `git branch -d <branch>`

## References

- Read `references/release-lines.md` for the two release lanes, the stable-line guarantees,
  the version-line map, and the intent-41 re-land playbook before starting any release
- When promoting a pre-release across channels (`--promote beta`/`--promote stable`) or
  tagging a historical release retroactively, read `references/promotion-and-tagging.md`
  for the exact commands and rules first
- Read `references/deprecations.md` for the full deprecation process, severity levels, deprecations.yml schema, and dismissal rules when adding or managing deprecations
