---
name: plastic:releasing
description: Use when merging a feature branch to main and tagging a release, bumping the version, or when the user says "release", "tag", or "ship it"
---

# Releasing

Merge, bump, tag, push. Annotated tags with changelogs. Semantic versioning.
Project configuration drives the workflow — no hardcoded assumptions.

## Checklist

- [ ] Read project config
- [ ] All tests pass (or verification skipped per config)
- [ ] Merge feature branch to main
- [ ] Bump version in configured version files
- [ ] Commit version bump
- [ ] Create annotated tag
- [ ] Push to remote with tags
- [ ] Run post-push actions (GitHub release, npm publish, etc.)
- [ ] Complete active intent

## Workflow

### 0. Read Project Config

Before anything else, determine which project we are releasing and load its config.

1. Read `~/.plastic/projects.yml` — find the project whose `path` matches the current working directory.
2. Extract the project slug (the key under `projects:`).
3. Read `~/.plastic/projects/{slug}/project.yml` — this contains the `release:` section.

Expected `release:` keys in project.yml:

```yaml
release:
  verify: "bin/rails test"              # command to run before release
  version_file: package.json            # single file containing the version
  version_files:                        # multiple files (overrides version_file)
    - package.json
    - .claude-plugin/plugin.json
  tag_format: "v{{version}}"            # tag naming pattern ({{version}} is replaced)
  on_green:                             # actions to run after push succeeds
    - github_release
    - npm_publish
  on_complete: commit_and_push          # what to do with the version bump commit
  on_red: stop                          # what to do if verification fails
```

**Fallback:** If no project.yml exists or it has no `release:` section, fall back to asking the user for each step — verify command, version files, tag format, and post-push actions.

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
git merge <branch-name> --no-ff -m "feat: merge intent [ID] — [description]"
```

Always `--no-ff` to preserve branch history in the merge commit.

### 4. Bump Version

Determine which files to update from project.yml:

- If `release.version_files` is set: update ALL listed files (they must stay in sync).
- Else if `release.version_file` is set: update that single file.
- Else: ask the user which files contain the version.

Update the version string in each file, then commit:

```bash
git add <version-files>
git commit -m "chore: bump version to X.Y.Z — [one-line summary]"
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
git tag -a <tag-name> -m "<tag-name> — [release name]

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
gh release create <tag-name> --title "<tag-name> — [release name]" --generate-notes --notes-start-tag <previous-tag>
```

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

### 8. Complete Active Intent

A release IS a delivery. The active intent that drove this work must be completed as part of the release process. This is NOT optional.

1. Read `~/.plastic/INDEX.md` → find active intent(s) related to this release
2. For each active intent being delivered:
   a. Write `outcome.md` with detailed results
   b. Write `## Outcome` summary in the intent file (reference the release tag)
   c. Update `## Insights` with final observations
   d. Move from `## Active` to `## Completed` in INDEX.md (with today's date)
   e. Update clusters to show `_(completed)_`
3. Auto-commit: `cd ~/.plastic && git add . && git commit -m "feat: complete intent <ID> — delivered in <tag-name>"`

**If no active intent exists for this release**, that itself is a problem — work happened outside the intent system. Log it and move on, but flag it.

## Conventions

- **Annotated tags only** — `git tag -a`, never lightweight tags
- **Tag format** — driven by `release.tag_format` in project.yml (default: `vX.Y.Z`)
- **Tag message** — first line: `<tag> — [short name]`, then blank line, then bullet changelog
- **Commit prefixes** — `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` (conventional commits)
- **Version files** — driven by project.yml; all listed files must always match
- **Branch cleanup** — delete merged feature branches: `git branch -d <branch>`

## Promotion

To promote a release across channels, use `--promote`:

```bash
plastic:releasing --promote beta    # promotes current alpha → beta
plastic:releasing --promote stable  # promotes current beta → stable
```

**Promotion rules:**
- Linear only: alpha → beta → stable. Cannot skip channels.
- `--promote beta`: reads version from `package.json`, changes `-alpha.N` suffix
  to `-beta.1`, publishes with `--tag beta`.
- `--promote stable`: reads version from `package.json`, strips pre-release suffix
  entirely (e.g., `1.0.0-beta.3` → `1.0.0`), publishes to `latest`.
- Version files are bumped and committed as in a normal release.
- An annotated tag is created for the promoted version.

## Retroactive Tagging

For repos without prior tags, tag historical releases:

```bash
git tag -a v0.1.0 <commit-sha> -m "v0.1.0 — [description]"
```

Use `git log --oneline` to find the right commits (look for version bump commits or major feature merges).

## References

- Read `references/deprecations.md` for the full deprecation process, severity levels, deprecations.yml schema, and dismissal rules when adding or managing deprecations
