---
name: plastic:releasing
description: Use when merging a feature branch to main and tagging a release, bumping the version, or when the user says "release", "tag", or "ship it"
---

# Releasing

Merge, bump, tag, push. Annotated tags with changelogs. Semantic versioning.

## Checklist

- [ ] All tests pass
- [ ] Merge feature branch to main
- [ ] Bump version in plugin.json and marketplace.json
- [ ] Commit version bump
- [ ] Create annotated tag
- [ ] Push to remote with tags

## Workflow

### 1. Verify Tests Pass

```bash
ruby test/read_config_test.rb && ruby test/config_template_test.rb
```

All tests must pass before release. Do not proceed if any fail.

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

Update BOTH files — they must stay in sync:
- `.claude-plugin/plugin.json` → `"version": "X.Y.Z"`
- `.claude-plugin/marketplace.json` → `"version": "X.Y.Z"`

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore: bump version to X.Y.Z — [one-line summary]"
```

### 5. Create Annotated Tag

Generate the changelog from commits since the last tag:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline --no-merges | grep -E "^[a-f0-9]+ (feat|fix|refactor):"
```

Create the tag with a multi-line message:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z — [release name]

- [changelog bullet points from feat/fix/refactor commits]"
```

### 6. Push

```bash
git push origin main --tags
```

### 7. GitHub Release

Create a GitHub release from the tag. Use `--generate-notes` to auto-generate changelog from commits since the previous tag:

```bash
gh release create vX.Y.Z --title "vX.Y.Z — [release name]" --generate-notes --notes-start-tag <previous-tag>
```

For the first release (no previous tag), write notes manually with `--notes "..."` instead.

## Conventions

- **Annotated tags only** — `git tag -a`, never lightweight tags
- **Tag format** — `vX.Y.Z` (lowercase v prefix)
- **Tag message** — first line: `vX.Y.Z — [short name]`, then blank line, then bullet changelog
- **Commit prefixes** — `feat:`, `fix:`, `refactor:`, `chore:`, `docs:` (conventional commits)
- **Version files** — plugin.json and marketplace.json always match
- **Branch cleanup** — delete merged feature branches: `git branch -d <branch>`

## Retroactive Tagging

For repos without prior tags, tag historical releases:

```bash
git tag -a v0.1.0 <commit-sha> -m "v0.1.0 — [description]"
```

Use `git log --oneline` to find the right commits (look for version bump commits or major feature merges).
