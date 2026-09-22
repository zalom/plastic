# ACTION_10 - end-intent: store_commit scoped commit, never git add -A

Covers spec.md AC: "`end-intent`'s `store_commit` step stages only the completing intent's own
changed paths, never `git add -A` at the store root, with a test proving an unrelated modified
file elsewhere in the store is not included in the commit." This is D17, the minimal safety
floor that makes 197 safe to ship before intent 178 (store worktrees) lands.

Discovery citation: `scripts/end-intent:330-341` (`store_commit`), called at
`scripts/end-intent:621`. `intent_dir` and `index_path` are already resolved in `main` before
that call site (`scripts/end-intent:522-523`:
`intent_dir = resolve_intent_dir(store, id)`; `index_path = opts[:index] ? expand(opts[:index])
: File.join(File.dirname(store), "INDEX.md")`).

File: `scripts/end-intent` (inside the worktree).

## 10a. `store_commit` takes the already-resolved paths instead of re-deriving them

Current (`scripts/end-intent:326-341`):
```ruby
# Best-effort store commit: never raises, never blocks the mechanical close.
# Returns true when a commit was created, false otherwise (not a git repo,
# nothing to commit, or the commit failed). Pins a local committer identity so
# the commit succeeds even with no ambient git config (hermetic).
def store_commit(store, id, disposition)
  root = git_toplevel(store)
  return false if root.nil?

  Open3.capture3("git", "-C", root, "add", "-A")
  _out, _err, status = Open3.capture3(
    "git", "-C", root,
    "-c", "user.name=Plastic", "-c", "user.email=plastic@localhost",
    "commit", "--quiet", "-m", "chore: complete intent #{id} (#{disposition})"
  )
  status.success?
end
```

Target:
```ruby
# Best-effort store commit: never raises, never blocks the mechanical close.
# Returns true when a commit was created, false otherwise (not a git repo, nothing to
# commit, or the commit failed). Pins a local committer identity so the commit succeeds
# even with no ambient git config (hermetic).
#
# SCOPED, never `git add -A` (D17, intent 197): stages only the completing intent's own
# directory plus the store's INDEX.md, by explicit relative path. An unrelated dirty file
# elsewhere in the store (another session's uncommitted work, a maintenance session's
# in-flight change) is left exactly as it was found, never swept into this commit. This is
# the safety floor that makes a concurrent maintenance session's change-plus-receipt safe on
# the shared store checkout before intent 178 (store worktrees) lands.
def store_commit(store, id, disposition, intent_dir:, index_path:)
  root = git_toplevel(store)
  return false if root.nil?

  paths = [intent_dir, index_path].select { |p| p && File.exist?(p) }
                                   .map { |p| relative_to(root, p) }
  return false if paths.empty?

  Open3.capture3("git", "-C", root, "add", "--", *paths)
  _out, _err, status = Open3.capture3(
    "git", "-C", root,
    "-c", "user.name=Plastic", "-c", "user.email=plastic@localhost",
    "commit", "--quiet", "-m", "chore: complete intent #{id} (#{disposition})"
  )
  status.success?
end

# `path`, relative to `root` (both absolute). Assumes `path` is inside `root` (true for
# both intent_dir and index_path here, since both are derived from `store`, itself always
# inside the same git repo `git_toplevel` resolved `root` from).
def relative_to(root, path)
  Pathname.new(File.expand_path(path)).relative_path_from(Pathname.new(File.expand_path(root))).to_s
end
```
Add `require "pathname"` near the top (`scripts/end-intent:67-72`) alongside the existing
`require "fileutils"` etc.

## 10b. Update the one call site

Current (`scripts/end-intent:620-621`):
```ruby
  # 4. Store auto-commit, unless --no-commit.
  store_commit(store, id, disposition) unless opts[:no_commit]
```

Target:
```ruby
  # 4. Store auto-commit, unless --no-commit. Scoped to this intent's own paths (D17):
  # never git add -A.
  store_commit(store, id, disposition, intent_dir: intent_dir, index_path: index_path) unless opts[:no_commit]
```
`intent_dir` and `index_path` are already in scope as local variables at this point in `main`
(`scripts/end-intent:522-523`); no new resolution needed.

## 10c. Tests - `test/end_intent_test.rb`

The existing `test_store_commit_lands_in_a_real_git_repo`
(`test/end_intent_test.rb:290-304`) already asserts a clean working tree after commit and a
matching log line; it continues to pass unmodified (both scoped paths are still staged and
committed, so the tree is still clean and the message is unchanged). Add:

```ruby
# FALSIFIABLE (208): an unrelated dirty file elsewhere in the store must survive the
# commit untouched and uncommitted (D17's whole point).
def test_store_commit_never_sweeps_an_unrelated_dirty_file
  build_intent
  write_index
  Open3.capture3("git", "init", "-q", @home)
  Open3.capture3("git", "-C", @home, "add", "-A")
  Open3.capture3("git", "-C", @home, "-c", "user.name=t", "-c", "user.email=t@t",
                 "commit", "-q", "-m", "seed")

  unrelated = File.join(@home, "unrelated-scratch.md")
  File.write(unrelated, "unrelated dirty content\n")

  _out, status = run_end_intent("--store", @store, "--id", "161", "--disposition", "delivered", "--index", @index)
  assert_equal 0, status

  log, = Open3.capture3("git", "-C", @home, "log", "--oneline")
  assert_match(/complete intent 161/, log)

  show, = Open3.capture3("git", "-C", @home, "show", "--stat", "HEAD")
  refute_match(/unrelated-scratch\.md/, show, "the unrelated file must not appear in the commit")

  status_out, = Open3.capture3("git", "-C", @home, "status", "--porcelain")
  assert_match(/unrelated-scratch\.md/, status_out, "the unrelated file must remain uncommitted/dirty")
end
```
Read `build_intent`/`write_index`/`run_end_intent`/`@store`/`@index`/`@home` from this file's
existing setup (already used by the two neighboring tests at lines 290-315); do not redefine
them.

## Verify

`ruby -Itest test/end_intent_test.rb` green, then the full suite.
