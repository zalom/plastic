# ACTION_5 - wire RevisionsWriter into rebuild-graph

Depends on ACTION_3 (`RevisionsWriter` exists). Covers the rebuild-graph half of spec.md AC7.
Discovery citation: `scripts/rebuild-graph` has zero "revisions" mentions today
(discovery.md section 2); the write path is `write_back`
(`scripts/rebuild-graph:143-160`).

File: `scripts/rebuild-graph` (inside the worktree).

## 5a. Require the new lib

Near the top (`scripts/rebuild-graph:24-27`), add:
```ruby
require_relative "lib/revisions_writer"
```

## 5b. Track write failures

In `initialize` (`scripts/rebuild-graph:47-65`), add `@write_failures = []` to the body and
`attr_reader ... , :write_failures` alongside the existing `attr_reader :plastic_home,
:dry_run, :audit_path` (line 67). Add:
```ruby
  def any_write_failures?
    !write_failures.empty?
  end
```

## 5c. `write_back` writes the receipt before the frontmatter change, per id

Current (`scripts/rebuild-graph:143-160`):
```ruby
  def write_back(store_list, nodes_by_store, results)
    store_list.each do |s|
      key = s[:key]
      new_nodes = results[key][:nodes]
      nodes_by_store[key].each do |id, original|
        rebuilt = new_nodes[id]
        next if rebuilt.nil?
        next if rebuilt[:sources] == original[:sources] && rebuilt[:chain] == original[:chain]

        content = File.read(original[:path])
        updated = FrontmatterWriter.rewrite_arrays(content,
                                                   sources: rebuilt[:sources],
                                                   chain: rebuilt[:chain])
        File.write(original[:path], updated) if updated != content
      end
    end
  end
```

Target:
```ruby
  def write_back(store_list, nodes_by_store, results)
    store_list.each do |s|
      key = s[:key]
      new_nodes = results[key][:nodes]
      changes_by_id = results[key][:changes].group_by { |c| c[:intent] }
      nodes_by_store[key].each do |id, original|
        rebuilt = new_nodes[id]
        next if rebuilt.nil?
        next if rebuilt[:sources] == original[:sources] && rebuilt[:chain] == original[:chain]

        content = File.read(original[:path])
        updated = FrontmatterWriter.rewrite_arrays(content,
                                                   sources: rebuilt[:sources],
                                                   chain: rebuilt[:chain])
        next if updated == content

        id_changes = changes_by_id[id] || []
        begin
          RevisionsWriter.append!(
            File.dirname(original[:path]),
            why: "graph rebuild: #{id_changes.map { |c| c[:kind] }.uniq.join(", ")}",
            rule: "graph-rebuild",
            prior_location: "#{File.basename(original[:path], ".md")}.md frontmatter - sources/chain",
            change: id_changes.map { |c| format_change(c) }.join("; ")
          )
        rescue RevisionsWriter::WriteFailed => e
          @write_failures << { id: id, error: e.message }
          next
        end
        File.write(original[:path], updated)
      end
    end
  end
```
`format_change` already exists (`scripts/rebuild-graph:225-243`) and renders one change kind
readably; reused verbatim, not duplicated. `changes_by_id` groups the existing
`results[key][:changes]` array (already built by `GraphRebuild.rebuild_store`, see
`scripts/rebuild-graph:129-134`) by `c[:intent]`, so this method makes zero new calls into
`GraphRebuild` and no new pure logic; it only threads existing data into the new receipt.

**Note:** `write_back` runs `unless dry_run` already (`scripts/rebuild-graph:137`, the caller),
so no dry-run guard is needed inside this method itself; a dry run never calls `write_back` at
all, matching the existing behavior (no receipt on a dry run, symmetric with project-links).

## 5d. Audit: surface write failures

In `render_audit` (`scripts/rebuild-graph:171-223`), right after the existing
`preserved_unknown` block (around line 184-192), add:
```ruby
    unless write_failures.empty?
      lines << "## Frontmatter changes that could NOT be written (revisions.md receipt failed)"
      lines << ""
      write_failures.each { |f| lines << "- #{f[:id]}: #{f[:error]}" }
      lines << ""
    end
```

## 5e. CLI: exit 1 on any write failure

In the `if $PROGRAM_NAME == __FILE__` block (`scripts/rebuild-graph:246-269`), after the
existing `puts` calls, add:
```ruby
  puts "Write failures (receipt could not be recorded, change withheld): #{tool.write_failures.size}" if tool.any_write_failures?
  exit 1 if tool.any_write_failures?
```
(Today this block has no explicit `exit` at all, i.e. it always exits 0; this is the first one,
matching project-links' existing `exit 1 if tool.any_failed?(results)` convention.)

## 5f. Tests - `test/rebuild_graph_test.rb`

The existing fixture already has a clean, single-id change to reuse: `plastic:80` has
`sources: ["22c"]`, which forces I1 to add `80` to `plastic:22c`'s `chain` (this is exactly
`test_i1_backlink_added_to_22c`'s case, `test/rebuild_graph_test.rb:120-126`). Use `22c` as the
target id (`projects/plastic/store/22c--slug/`):

```ruby
def test_applied_frontmatter_change_writes_a_revisions_md_receipt
  RebuildGraph.new(plastic_home: @home, audit_path: @audit).run
  revisions = File.read(File.join(@home, "projects", "plastic", "store", "22c--slug", "revisions.md"))
  assert_includes revisions, "## Revision v1"
  assert_includes revisions, "[rule: graph-rebuild]"
  assert_includes revisions, "i1_backlink"
end

# FALSIFIABLE (208): append-only across two separate runs that each make a real change.
def test_second_applied_change_appends_v2_not_overwrite
  RebuildGraph.new(plastic_home: @home, audit_path: @audit).run # v1
  # Force a second real change to 22c: add another backlink source pointing at it.
  write_intent(File.join(@home, "projects", "plastic", "store"), "83", sources: ["22c"], chain: [])
  RebuildGraph.new(plastic_home: @home, audit_path: @audit).run # v2

  revisions = File.read(File.join(@home, "projects", "plastic", "store", "22c--slug", "revisions.md"))
  assert_equal 2, revisions.scan(/^## Revision v\d+/).length
  assert_includes revisions, "## Revision v1"
  assert_includes revisions, "## Revision v2"
end

def test_dry_run_writes_no_revisions_md
  RebuildGraph.new(plastic_home: @home, dry_run: true, audit_path: @audit).run
  refute File.exist?(File.join(@home, "projects", "plastic", "store", "22c--slug", "revisions.md"))
end

# FALSIFIABLE (208): a receipt failure must refuse the frontmatter write (chmod the
# target dir read-only), confirm the .md is untouched, any_write_failures? is true, and the
# CLI process exits 1.
def test_revisions_write_failure_refuses_the_frontmatter_write
  dir = File.join(@home, "projects", "plastic", "store", "22c--slug")
  before = File.read(File.join(dir, "22c--slug.md"))
  File.chmod(0o500, dir)
  begin
    tool = RebuildGraph.new(plastic_home: @home, audit_path: @audit)
    tool.run
    assert tool.any_write_failures?
    assert_equal before, File.read(File.join(dir, "22c--slug.md")),
      "the frontmatter must be untouched when its receipt cannot be written"
  ensure
    File.chmod(0o700, dir)
  end
end
```

## Verify

`ruby -Itest test/rebuild_graph_test.rb` green, then the full suite.
