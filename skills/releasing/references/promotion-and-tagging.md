# Promotion, Retroactive Tagging, and Worktree Merge Rationale

Occasional variant paths off the main release workflow: promoting a pre-release
across channels, tagging historical releases retroactively, and the deep rationale
for why the intent's worktree is merged before removal.

## Table of Contents

- [Worktree merge-then-remove rationale](#worktree-merge-then-remove-rationale)
- [Promotion](#promotion)
- [Retroactive Tagging](#retroactive-tagging)

## Worktree merge-then-remove rationale

**Worktree-isolated intents (intent 73c3).** When the intent was delivered in a Plastic
worktree (the bridge has a provisioned `worktree` block), its code lives on the branch
`plastic/{id}--{slug}` inside `<repo>/.claude/worktrees/{id}--{slug}`, not on a hand-made
feature branch. The merge-then-remove of that worktree is handled together with cleanup in
Workflow step 9, which merges `plastic/{id}--{slug}` into the default branch BEFORE removing the
worktree. If you already merged here by hand, step 9 is a clean no-op merge ("Already up to
date") and proceeds straight to removal. Do not delete the worktree before its branch is
merged, or the work is lost.

A release is the merge-then-remove path for the intent's worktrees. This is the one place
the merge-vs-remove policy lands on "merge": the intent's code branch (`plastic/{id}--{slug}`)
is merged back into the repo's default branch BEFORE the worktree is removed, so the
integrated work is never lost. (The disarm path in `plastic-auto`, by contrast, is a plain
remove because no release is merging the branch.)

`Worktree.finish` is fail-open and idempotent: a conflicting merge is aborted and logged (the
worktree is still removed rather than stranded), and a second call with the block already
cleared is a no-op.

## Promotion

To promote a release across channels, use `--promote`:

```bash
plastic-releasing --promote beta    # promotes current alpha → beta
plastic-releasing --promote stable  # promotes current beta → stable
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
git tag -a v0.1.0 <commit-sha> -m "v0.1.0 - [description]"
```

Use `git log --oneline` to find the right commits (look for version bump commits or major feature merges).
