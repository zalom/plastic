# ACTION_4 - wire RevisionsWriter into project-links

Depends on ACTION_1 (the `only:` param exists), ACTION_2 (the `dead` bucket exists), ACTION_3
(`RevisionsWriter` exists). Covers the project-links half of spec.md AC7: "a test exists
proving [project-links] actually writes the entry on a fixture change and appends `vN+1`
rather than overwriting when the file already exists."

**Design: receipt-before-change, not change-then-receipt.** `RevisionsWriter.append!` is called
FIRST; only if it succeeds does `File.write(node[:path], updated)` run. This makes "refuse to
proceed without one" structural rather than a rollback: there is never a moment where the
`## Links` change exists on disk without its receipt, because the receipt is written first. If
`append!` raises (`RevisionsWriter::WriteFailed`), the entry is recorded as `:failed` (same
bucket the resolver-miss path already uses) and the intent file is never touched.

File: `scripts/project-links` (inside the worktree).

## 4a. Require the new lib

Near the top (`scripts/project-links:36-40`), add:
```ruby
require_relative "lib/revisions_writer"
```

## 4b. `project_store`: write the receipt before the file, on every real change

Current tail of the per-id loop (`scripts/project-links:179-189`):
```ruby
      if updated == content
        entries << { id: id, status: :unchanged,
                     orphans_preserved: kept, orphans_dropped_optin: dropped_optin }
        next
      end

      status = had_links ? :regenerated : :added
      File.write(node[:path], updated) unless dry_run
      entries << { id: id, status: status, before: old_text, after: section_text,
                   orphans_preserved: kept, orphans_dropped_optin: dropped_optin }
```

Target (adds `orphans_dead: dead` per ACTION_2, and the receipt-before-write step; dry-run
still never writes anything, including the receipt, matching the tool's existing "a dry run
must not stomp" discipline):
```ruby
      if updated == content
        entries << { id: id, status: :unchanged, orphans_preserved: kept,
                     orphans_dropped_optin: dropped_optin, orphans_dead: dead }
        next
      end

      status = had_links ? :regenerated : :added

      unless dry_run
        begin
          RevisionsWriter.append!(
            File.dirname(node[:path]),
            why: revision_why(status, kept, dropped_optin, dead),
            rule: "links-projection",
            prior_location: "#{node[:basename]}.md ## Links",
            change: revision_change(old_text, section_text)
          )
        rescue RevisionsWriter::WriteFailed => e
          entries << { id: id, status: :failed, error: e.message,
                       orphans_preserved: [], orphans_dropped_optin: [], orphans_dead: [] }
          next
        end
        File.write(node[:path], updated)
      end

      entries << { id: id, status: status, before: old_text, after: section_text,
                   orphans_preserved: kept, orphans_dropped_optin: dropped_optin, orphans_dead: dead }
```

Also add `orphans_dead: []` to the two OTHER `entries <<` hashes in the method (the
`UnresolvedRef`/`AmbiguousLinks` rescue at the top, per ACTION_2's uniform-key note).

## 4c. Two small private helpers for the `Why`/`Change` text

Add near `orphan_split` (private-by-convention, same style as the rest of the class):
```ruby
  # Renders the one-sentence "Why" for a project-links-authored receipt. Free text; the
  # [rule: tag] suffix is appended by RevisionsWriter itself, not here.
  def revision_why(status, kept, dropped_optin, dead)
    parts = []
    parts << (status == :added ? "added a missing ## Links section" : "regenerated ## Links to match frontmatter")
    parts << "dropped #{dead.size} unresolvable reference(s)" unless dead.empty?
    parts << "dropped #{dropped_optin.size} unbacked-but-resolvable reference(s) (--drop-unbacked-links)" unless dropped_optin.empty?
    parts.join("; ")
  end

  def revision_change(before_text, after_text)
    "## Links regenerated (before -> after)\n\n  BEFORE:\n" \
      "#{block_lines(before_text).map { |l| "    #{l}" }.join("\n")}\n\n  AFTER:\n" \
      "#{block_lines(after_text).map { |l| "    #{l}" }.join("\n")}"
  end
```
`block_lines` already exists (`scripts/project-links:341-346`); reuse it verbatim, do not
duplicate.

## 4d. Tests - `test/project_links_test.rb`

```ruby
def test_applied_change_writes_a_revisions_md_receipt
  run_tool
  revisions = File.read(File.join(@home, "projects", "plastic", "store", "11--child", "revisions.md"))
  assert_includes revisions, "## Revision v1"
  assert_includes revisions, "[rule: links-projection]"
end

# FALSIFIABLE (208): append-only. Run the tool twice against the same fixture, changing
# the target's frontmatter between runs so a SECOND real change happens, and confirm v2 is
# appended rather than v1 being overwritten.
def test_second_applied_change_appends_v2_not_overwrite
  run_tool # v1 written
  # Mutate 11--child's frontmatter so a second real projection change happens.
  path = File.join(@home, "projects", "plastic", "store", "11--child", "11--child.md")
  content = File.read(path)
  File.write(path, content.sub('sources: ["global:40"]', 'sources: ["global:40", "13"]'))

  run_tool # v2 written

  revisions = File.read(File.join(@home, "projects", "plastic", "store", "11--child", "revisions.md"))
  assert_includes revisions, "## Revision v1"
  assert_includes revisions, "## Revision v2"
  assert_equal 2, revisions.scan(/^## Revision v\d+/).length
end

def test_dry_run_writes_no_revisions_md
  run_tool(dry_run: true)
  refute File.exist?(File.join(@home, "projects", "plastic", "store", "11--child", "revisions.md"))
end

# FALSIFIABLE (208): a receipt failure must refuse the file write, not silently drop the
# receipt. Point RevisionsWriter at an unwritable location by making the intent's own
# directory read-only, and confirm the ## Links file is untouched and the id is reported
# :failed (making any_failed? true / exit 1).
def test_revisions_write_failure_refuses_the_links_write
  dir = File.join(@home, "projects", "plastic", "store", "11--child")
  before = File.read(File.join(dir, "11--child.md"))
  File.chmod(0o500, dir) # read+execute only, no write
  begin
    tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit)
    results = tool.run
    assert tool.any_failed?(results)
    assert_equal before, File.read(File.join(dir, "11--child.md")),
      "the intent file must be untouched when its receipt cannot be written"
  ensure
    File.chmod(0o700, dir) # restore for teardown's FileUtils.remove_entry
  end
end
```

## Verify

`ruby -Itest test/project_links_test.rb` green, then the full suite.
