# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

load File.expand_path("../scripts/rebuild-graph", __dir__)

# ACTION 3 — hermetic executable tests. Build temp stores under Dir.mktmpdir,
# run the tool with --plastic-home <tmp>, assert rewritten frontmatter, audit
# content, and a verified no-op on a second run. No real-store access.
class RebuildGraphTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-rebuild-test")
    build_fixture_stores
    @audit = File.join(@home, "audit.md")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture builders ---

  def write_intent(store_dir, id, sources:, chain:, block_sources: false)
    dir = File.join(store_dir, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    src_yaml = if block_sources
                 "sources:\n" + (sources.empty? ? "sources: []\n" : sources.map { |s| "- '#{s}'\n" }.join)
               else
                 "sources: #{flow(sources)}\n"
               end
    src_yaml = "sources: []\n" if block_sources && sources.empty?
    content = +"---\n"
    content << "id: \"#{id}\"\n"
    content << "intent: Test #{id}\n"
    content << src_yaml
    content << "chain: #{flow(chain)}\n"
    content << "created: 2026-06-01\n"
    content << "author: test\n"
    content << "tags: [t]\n"
    content << "---\n\n## Intent\nBody #{id}.\n\n## Links\n- untouched\n"
    File.write(File.join(dir, "#{id}--slug.md"), content)
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def write_index(path, relocated)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n#{relocated}\n\n## Completed\n")
  end

  def build_fixture_stores
    global = File.join(@home, "store")
    plastic = File.join(@home, "projects", "plastic", "store")
    knowdb = File.join(@home, "projects", "knowdb", "store")
    [global, plastic, knowdb].each { |d| FileUtils.mkdir_p(d) }

    # Global: a NEW unrelated global:24 (the impostor) + the relocation source ids,
    # plus 1a2 (healthy cross-store chain target).
    write_intent(global, "24", sources: [], chain: [])               # impostor
    write_intent(global, "1a2", sources: [], chain: ["knowdb:1"])    # healthy cross-store chain

    # Plastic: 11 → global:24 (must become 22c, not impostor); 13 → global:14a,75
    # (14a→19a); targets 22c, 19a, 75; an I3 overlap; an I1 backlink case; an I2
    # relational chain entry.
    write_intent(plastic, "11", sources: ["global:24"], chain: [])
    write_intent(plastic, "13", sources: ["global:14a", "75", "75"], chain: ["19a"]) # dup + post-resolve I3
    write_intent(plastic, "19a", sources: [], chain: [])
    write_intent(plastic, "22c", sources: [], chain: [])
    write_intent(plastic, "75", sources: [], chain: [])
    write_intent(plastic, "80", sources: ["22c"], chain: [])         # I1: 22c.chain += 80
    write_intent(plastic, "81", sources: [], chain: ["82"])          # I2 relational chain
    write_intent(plastic, "82", sources: [], chain: [])

    # Knowdb: 1 → global:1a2 (healthy cross-store, stays). Block-style sources.
    write_intent(knowdb, "1", sources: ["global:1a2"], chain: [], block_sources: true)

    write_index(File.join(@home, "INDEX.md"),
                "- global:14a → project:19a, global:24 → project:22c")
    write_index(File.join(@home, "projects", "plastic", "INDEX.md"), "(none)")
    write_index(File.join(@home, "projects", "knowdb", "INDEX.md"), "(none)")
  end

  def read_fm(rel)
    content = File.read(File.join(@home, rel))
    IntentValidator.parse_frontmatter_text(content)
  end

  def run_tool(dry_run: false)
    RebuildGraph.new(plastic_home: @home, dry_run: dry_run, audit_path: @audit).run
  end

  # --- assertions ---

  def test_global_24_repoints_to_bare_22c_not_impostor
    run_tool
    fm = read_fm("projects/plastic/store/11--slug/11--slug.md")
    assert_equal ["22c"], fm["sources"]
  end

  def test_global_14a_to_19a_keep_75
    run_tool
    fm = read_fm("projects/plastic/store/13--slug/13--slug.md")
    assert_equal ["19a", "75"], fm["sources"]
  end

  def test_post_resolution_i3_drops_19a_from_chain
    run_tool
    fm = read_fm("projects/plastic/store/13--slug/13--slug.md")
    # 19a now in sources (from 14a) and was in chain → dropped from chain (I3)
    refute_includes fm["chain"], "19a"
  end

  def test_i1_backlink_added_to_22c
    run_tool
    fm = read_fm("projects/plastic/store/22c--slug/22c--slug.md")
    # 80.sources=[22c] and 11.sources collapsed to [22c] → both backlink
    assert_includes fm["chain"], "80"
    assert_includes fm["chain"], "11"
  end

  def test_i2_relational_chain_preserved
    run_tool
    fm81 = read_fm("projects/plastic/store/81--slug/81--slug.md")
    fm82 = read_fm("projects/plastic/store/82--slug/82--slug.md")
    assert_equal ["82"], fm81["chain"], "relational chain entry kept"
    assert_equal [], fm82["sources"], "no reciprocal source synthesized"
  end

  def test_healthy_cross_store_refs_unchanged
    run_tool
    knowdb1 = read_fm("projects/knowdb/store/1--slug/1--slug.md")
    global1a2 = read_fm("store/1a2--slug/1a2--slug.md")
    assert_equal ["global:1a2"], knowdb1["sources"]
    assert_equal ["knowdb:1"], global1a2["chain"]
  end

  def test_block_style_preserved
    run_tool
    raw = File.read(File.join(@home, "projects/knowdb/store/1--slug/1--slug.md"))
    # block style sources retained (single quotes, separate `-` lines), unchanged
    assert_includes raw, "sources:\n- 'global:1a2'\n"
  end

  def test_links_section_untouched
    run_tool
    raw = File.read(File.join(@home, "projects/plastic/store/11--slug/11--slug.md"))
    assert_includes raw, "## Links\n- untouched"
  end

  def test_audit_written_with_grouped_kinds
    run_tool
    audit = File.read(@audit)
    assert_includes audit, "# Audit: store-wide sources/chain graph rebuild (intent 49)"
    assert_includes audit, "Cross-store collapses"
    assert_includes audit, "I1 backlinks added"
    assert_includes audit, "11.sources: global:24 → 22c"
  end

  def test_dry_run_does_not_write_files_but_writes_audit
    before = File.read(File.join(@home, "projects/plastic/store/11--slug/11--slug.md"))
    run_tool(dry_run: true)
    after = File.read(File.join(@home, "projects/plastic/store/11--slug/11--slug.md"))
    assert_equal before, after, "dry run must not rewrite intent files"
    assert File.exist?(@audit), "dry run still emits the audit"
    assert_includes File.read(@audit), "(DRY RUN)"
  end

  def test_idempotent_second_run_is_noop
    run_tool
    snapshot = file_snapshot
    second = run_tool
    assert_equal snapshot, file_snapshot, "second run must change no files"
    total = second.values.sum { |r| r[:changes].size }
    assert_equal 0, total, "second run must record zero changes"
  end

  def file_snapshot
    # Snapshot only intent files under store/ dirs; the audit carries a timestamp
    # and is not store data.
    Dir.glob(File.join(@home, "**", "store", "**", "*.md")).sort.to_h { |p| [p, File.read(p)] }
  end
end
