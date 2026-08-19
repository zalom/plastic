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

Promotion is not a CLI flag; there is no `--promote` command. It is a set of steps the
agent performs during the releasing workflow, reusing the normal release mechanics
(version bump, tag, `npm publish` with the channel's dist-tag, GitHub release):

```bash
# Promote alpha → beta: set version files from -alpha.N to -beta.1, commit, tag, then
npm publish --access public --tag beta

# Promote beta → stable: strip the pre-release suffix (e.g., 1.0.0-beta.3 → 1.0.0),
# commit, tag, then
npm publish --access public          # no --tag flag publishes to latest
```

**Promotion rules:**
- Linear only: alpha → beta → stable. Cannot skip channels.
- Version files are bumped and committed as in a normal release.
- An annotated tag is created for the promoted version, and the GitHub release is cut
  as in the normal workflow (`gh release create ... --latest` for stable).
- To point a channel at an already-published version without republishing, move the
  dist-tag directly: `npm dist-tag add @zalom/plastic@<version> <channel>`. To move the
  GitHub "Latest" badge: `gh release edit <tag> --latest`.

## Retroactive Tagging

For repos without prior tags, tag historical releases:

```bash
git tag -a v0.1.0 <commit-sha> -m "v0.1.0 - [description]"
```

Use `git log --oneline` to find the right commits (look for version bump commits or major feature merges).
