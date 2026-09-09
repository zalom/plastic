# ACTION_6 - restore-intent-v1: prove append-only vN+1 behavior with a new test

Covers the restore-intent-v1 half of spec.md AC7: "a test exists proving each tool actually
writes the entry on a fixture change and appends `vN+1` rather than overwriting when the file
already exists." `restore-intent-v1` already writes a receipt correctly
(`scripts/restore-intent-v1:264-277`, `append_revision`: reads existing-or-seeds, scans
`## Revision v(\d+)`, takes `max + 1`, appends). Discovery citation: this is the ONE tool that
already does what R1/R6 describe (discovery.md section 2). **No production code changes in
this action** - only a new test proving the append-only behavior the code already has, closing
the one gap in the existing suite (the existing test,
`test_revisions_gains_exactly_one_entry_naming_reverted_files`, only ever runs the tool ONCE
against a fixture with no pre-existing `revisions.md`, so it cannot distinguish "always writes
v1" from "correctly appends vN+1").

If, while writing this test, the behavior turns out NOT to hold (a real gap, not merely
untested), fix `append_revision` in `scripts/restore-intent-v1` minimally to match
`RevisionsWriter.next_revision_number`'s exact algorithm (ACTION_3) - do not silently accept a
red test.

File: `test/restore_intent_v1_test.rb` (inside the worktree). Uses the existing
`seed_124_131_shape` fixture helper (`test/restore_intent_v1_test.rb:76-91`), `RESTORE`
constant, and `relative_to_home`/`git`/`commit_all` helpers already defined in this file - read
them first, do not redefine.

## 6a. New test - pre-existing revisions.md is preserved, new entry appends as v2

```ruby
# FALSIFIABLE (208): append-only. Seed the target intent with a PRE-EXISTING
# revisions.md (v1, unrelated to this restore) before running --apply, and confirm the
# restore's own entry lands as v2, with v1's exact text still present verbatim.
def test_preexisting_revisions_md_is_preserved_and_new_entry_appends_as_v2
  a_dir, a_id, v1_sha = seed_124_131_shape

  preexisting = "# revisions.md\n\n## Revision v1 - 2026-01-01-00:00\n" \
                "- Why: unrelated prior structural fix [rule: unsanctioned-section]\n" \
                "- Prior location: #{File.basename(a_dir)}.md - ## Scratch\n" \
                "- Content held:\n\n  ## Scratch\n  old junk\n"
  revisions_path = File.join(a_dir, "revisions.md")
  File.write(revisions_path, preexisting)

  out, status = Open3.capture2(
    RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply"
  )
  assert_equal 0, status.exitstatus, "restore should succeed: #{out}"

  revisions = File.read(revisions_path)
  assert_includes revisions, "## Revision v1 - 2026-01-01-00:00", "the pre-existing v1 entry must survive verbatim"
  assert_includes revisions, "unrelated prior structural fix", "v1's exact text must not be altered"
  assert_includes revisions, "## Revision v2", "the restore's own entry must append as v2, not overwrite v1"
  assert_equal 2, revisions.scan(/^## Revision v\d+/).length
  assert_includes revisions, "restored-to-v1", "v2 must carry this tool's own rule tag"
end

# FALSIFIABLE (208) counterpart: a SECOND restore run (idempotent no-op, since the
# intent is already at v1) must NOT append a spurious v3 when nothing actually changed.
# (Establishes the "no-op yields no entry" floor so the test above is not vacuously
# passing on a tool that appends unconditionally on every invocation.)
def test_idempotent_second_restore_appends_no_further_entry_when_already_at_v1
  a_dir, a_id, v1_sha = seed_124_131_shape

  Open3.capture2(RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply")
  revisions_path = File.join(a_dir, "revisions.md")
  after_first = File.read(revisions_path)
  count_after_first = after_first.scan(/^## Revision v\d+/).length

  Open3.capture2(RbConfig.ruby, RESTORE, a_id, "--at", v1_sha, "--plastic-home", @home, "--apply")
  after_second = File.read(revisions_path)

  # NOTE: read scripts/restore-intent-v1's append_revision (lines 264-277) and
  # RestoreIntentV1.compute_graph before asserting the exact count here: if the tool's
  # current behavior is "always append on --apply regardless of no-op," this test should
  # assert count_after_first + 1 instead of an unchanged count, and that gap (appending a
  # content-free entry on a true no-op) should be noted as a finding for the executor to
  # fix under this same action, since D14's intent is "record every ACTUAL change," not
  # every invocation. Whichever the real behavior is, pin it explicitly rather than leave
  # it undiscovered.
  assert after_second.scan(/^## Revision v\d+/).length >= count_after_first
end
```

## Verify

`ruby -Itest test/restore_intent_v1_test.rb` green, then the full suite. If
`test_idempotent_second_restore_appends_no_further_entry_when_already_at_v1` reveals the tool
appends unconditionally on a true no-op, treat that as an in-scope minimal fix under this same
action (guard `append_revision`'s call site so it is skipped when `prose_changes` is empty AND
`graph[:sources]`/`graph[:chain]` are unchanged from `current_fm`), re-running both tests green
afterward. Do not expand scope beyond that one guard.
