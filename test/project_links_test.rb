# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

load File.expand_path("../scripts/project-links", __dir__)

# ACTION 3 — hermetic executable tests. Build temp stores under Dir.mktmpdir, run
# the tool with --plastic-home <tmp>, assert the projected `## Links` sections,
# cross-store form, empty-state, idempotency, resolver-miss-fails-loud, and the
# dry-run audit discipline. No real-store access.
class ProjectLinksTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-links-test")
    build_fixture_stores
    @audit = File.join(@home, "audit.md")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- fixture builders ---

  def write_intent(store_dir, basename, id:, intent:, sources:, chain:, links: "## Links\n- legacy placeholder\n")
    dir = File.join(store_dir, basename)
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << "id: \"#{id}\"\n"
    content << "intent: \"#{intent}\"\n"
    content << "sources: #{flow(sources)}\n"
    content << "chain: #{flow(chain)}\n"
    content << "created: 2026-06-01\n"
    content << "author: test\n"
    content << "tags: [t]\n"
    content << "---\n\n# #{intent}\n\n## Intent\nBody #{id}.\n\n"
    content << links if links
    File.write(File.join(dir, "#{basename}.md"), content)
  end

  def flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def write_index(path, body = "(none)")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# Index\n\n## Relocated\n#{body}\n\n## Completed\n")
  end

  def build_fixture_stores
    global = File.join(@home, "store")
    plastic = File.join(@home, "projects", "plastic", "store")
    [global, plastic].each { |d| FileUtils.mkdir_p(d) }

    # Global: 40 (a source target), 1a2 (chains cross-store to plastic:11).
    write_intent(global, "40--store-graph", id: "40", intent: "Build the store graph",
                 sources: [], chain: [])
    write_intent(global, "1a2--cross", id: "1a2", intent: "Cross intent",
                 sources: [], chain: ["plastic:11"])

    # Plastic: 11 sources 40 (cross-store) + chain back to global:1a2; 12 sources 11
    # (same-store); 13 empty (empty-state); 99 dangling source (resolver miss).
    write_intent(plastic, "11--child", id: "11", intent: "Child of forty",
                 sources: ["global:40"], chain: ["global:1a2"],
                 links: "## Links\n<!-- Retroactive (intent 60b): heading only. -->\n")
    write_intent(plastic, "12--grandchild", id: "12", intent: "Grandchild",
                 sources: ["11"], chain: [], links: nil) # no ## Links → added
    write_intent(plastic, "13--lonely", id: "13", intent: "Lonely intent",
                 sources: [], chain: [])
    write_intent(plastic, "99--dangler", id: "99", intent: "Dangler",
                 sources: ["does-not-exist"], chain: [])

    write_index(File.join(@home, "INDEX.md"))
    write_index(File.join(@home, "projects", "plastic", "INDEX.md"))
  end

  def read(rel)
    File.read(File.join(@home, rel))
  end

  def run_tool(dry_run: false, audit_path: nil)
    ProjectLinks.new(plastic_home: @home, dry_run: dry_run, audit_path: audit_path || @audit).run
  end

  # --- assertions ---

  def test_dry_run_changes_no_files_but_writes_audit
    before = read("projects/plastic/store/11--child/11--child.md")
    run_tool(dry_run: true)
    after = read("projects/plastic/store/11--child/11--child.md")
    assert_equal before, after, "dry run must not rewrite intent files"
    assert File.exist?(@audit)
    assert_includes File.read(@audit), "(DRY RUN)"
  end

  def test_apply_projects_same_store_source
    run_tool
    links = read("projects/plastic/store/12--grandchild/12--grandchild.md")
    assert_includes links, "## Links\n- [[11--child|Child of forty]]\n"
  end

  def test_apply_projects_cross_store_source_and_chain_ordering
    run_tool
    body = read("projects/plastic/store/11--child/11--child.md")
    # source global:40 first (cross-store), then chain global:1a2.
    src = "- [[global:40--store-graph|Build the store graph]]"
    chn = "- [[global:1a2--cross|Cross intent]]"
    assert_includes body, src
    assert_includes body, chn
    assert body.index(src) < body.index(chn), "source must precede chain"
  end

  def test_cross_store_entry_shape
    run_tool
    body = read("store/1a2--cross/1a2--cross.md")
    assert_includes body, "- [[plastic:11--child|Child of forty]]"
  end

  def test_empty_state_block
    run_tool
    body = read("projects/plastic/store/13--lonely/13--lonely.md")
    assert_includes body,
                    "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n"
  end

  def test_section_added_when_missing
    # 12 had no ## Links; it should be added in canonical position and validate.
    run_tool
    body = read("projects/plastic/store/12--grandchild/12--grandchild.md")
    assert_includes body, "## Links\n"
  end

  def test_resolver_miss_fails_loud_and_does_not_write
    before = read("projects/plastic/store/99--dangler/99--dangler.md")
    results = run_tool
    after = read("projects/plastic/store/99--dangler/99--dangler.md")
    assert_equal before, after, "a failed intent must not be written"
    entry = results["project:plastic"][:entries].find { |e| e[:id] == "99" }
    assert_equal :failed, entry[:status]
    refute_includes after, "[[does-not-exist", "no guessed/bare link emitted"
  end

  def test_idempotent_second_apply_is_noop
    run_tool
    snapshot = file_snapshot
    second = run_tool
    assert_equal snapshot, file_snapshot, "second apply must change no files"
    %w[project:plastic global].each do |key|
      c = second[key][:counts]
      assert_equal 0, c[:regenerated], "#{key}: zero regenerated on second run"
      assert_equal 0, c[:added], "#{key}: zero added on second run"
    end
  end

  def test_only_links_section_changes
    before = read("projects/plastic/store/11--child/11--child.md")
    run_tool
    after = read("projects/plastic/store/11--child/11--child.md")
    # Frontmatter + everything before ## Links is byte-identical.
    pre_before = before[0...before.index("## Links")]
    pre_after = after[0...after.index("## Links")]
    assert_equal pre_before, pre_after, "only the ## Links section may change"
  end

  def test_audit_reports_counts_and_failed
    run_tool
    audit = File.read(@audit)
    assert_includes audit, "# Audit: store-wide ## Links projection (intent 72)"
    assert_includes audit, "FAILED"
    assert_includes audit, "99:"
  end

  def test_dry_run_default_audit_writes_sibling_not_canonical
    canonical = File.join(@home, ProjectLinks::DEFAULT_AUDIT_REL)
    sibling = canonical.sub(/\.md\z/, ".dry-run.md")
    ProjectLinks.new(plastic_home: @home, dry_run: true).run
    assert File.exist?(sibling), "dry run writes the .dry-run.md sibling"
    refute File.exist?(canonical), "dry run must not write the canonical audit"
  end

  def file_snapshot
    Dir.glob(File.join(@home, "**", "store", "**", "*.md")).sort.to_h { |p| [p, File.read(p)] }
  end

  # --- ACTION_1 (intent 192): orphan-candidate preservation ---

  # Adds two more plastic-store intents on top of build_fixture_stores: "14--old-sibling"
  # (a real, resolvable target) and "21--subject", whose OWN Links section carries a
  # hand-typed, frontmatter-unbacked line pointing at 14 (resolvable: preserve), plus a
  # broken/garbage line that resolves nowhere (dead: still silently dropped).
  def add_orphan_fixture
    plastic = File.join(@home, "projects", "plastic", "store")
    write_intent(plastic, "14--old-sibling", id: "14", intent: "Old sibling intent",
                 sources: [], chain: [])
    write_intent(plastic, "21--subject", id: "21", intent: "Subject intent",
                 sources: [], chain: [],
                 links: "## Links\n- [[14--old-sibling|Old sibling intent]]\n" \
                        "- [[99--nowhere|Nowhere at all]]\n")
  end

  def test_unbacked_but_resolvable_link_is_preserved_and_reported
    add_orphan_fixture
    run_tool
    body = read("projects/plastic/store/21--subject/21--subject.md")
    assert_includes body, "- [[14--old-sibling|Old sibling intent]]",
                     "an unbacked line that still resolves must be preserved, not deleted"
    audit = File.read(@audit)
    assert_includes audit, "Orphan candidates preserved"
    assert_includes audit, "21: -> 14--old-sibling"
  end

  # ACTION_2 (intent 197): the dead line is still dropped from the file (nothing real to
  # preserve), but it is no longer silent: it must now surface under the new "Malformed
  # references" finding, never misreported as a preserved or opt-in-dropped orphan (it is
  # neither, since it resolves to no real intent at all).
  def test_unbacked_and_dead_link_is_dropped_but_reported_as_malformed
    add_orphan_fixture
    run_tool
    body = read("projects/plastic/store/21--subject/21--subject.md")
    refute_includes body, "99--nowhere", "a line that resolves nowhere must still be dropped"

    audit = File.read(@audit)
    assert_includes audit, "Malformed references found"
    assert_includes audit, "- 21: -> 99--nowhere"

    preserved_section = audit[/### Orphan candidates preserved.*?\n\n/m].to_s
    refute_includes preserved_section, "99--nowhere",
                    "a dead ref must never be misreported as a preserved orphan candidate"
  end

  def test_drop_unbacked_links_flag_removes_resolvable_orphan_and_reports_it_separately
    add_orphan_fixture
    ProjectLinks.new(plastic_home: @home, audit_path: @audit, drop_unbacked_links: true).run
    body = read("projects/plastic/store/21--subject/21--subject.md")
    refute_includes body, "14--old-sibling",
                    "--drop-unbacked-links must delete an orphan candidate when passed"
    audit = File.read(@audit)
    assert_includes audit, "Orphan candidates DROPPED (--drop-unbacked-links)"
    assert_includes audit, "21: -> 14--old-sibling"
  end

  def test_orphan_preservation_is_idempotent
    add_orphan_fixture
    run_tool
    snapshot = file_snapshot
    run_tool
    assert_equal snapshot, file_snapshot, "a second run with a preserved orphan must change nothing"
  end

  # --- ACTION_1 (intent 197): --intent single-intent scope ---

  def test_intent_scope_regenerates_only_the_named_intent
    # build_fixture_stores (setup) already seeds "11--child" (project:plastic) with a
    # stale ## Links (heading-only comment) against real sources ["global:40"]/chain
    # ["global:1a2"]. Scope to "11" only and confirm every other fixture file is untouched.
    before = Dir.glob(File.join(@home, "**", "*.md")).to_h { |f| [f, File.read(f)] }

    tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "11")
    tool.run

    before.each do |path, original|
      if path.end_with?("11--child/11--child.md")
        refute_equal original, File.read(path), "the scoped intent must be regenerated"
      else
        assert_equal original, File.read(path), "an unscoped intent must be byte-identical: #{path}"
      end
    end
  end

  def test_intent_scope_with_unknown_id_changes_nothing
    before = Dir.glob(File.join(@home, "**", "*.md")).to_h { |f| [f, File.read(f)] }
    tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "no-such-id")
    tool.run
    before.each { |path, original| assert_equal original, File.read(path) }
  end

  # FALSIFIABLE (208) and load-bearing: this is the EXACT real-world shape Task 13 depends
  # on (ids 26 and 15 both collide across real stores today). A bare --intent matching more
  # than one store must abort loud, listing every candidate, rather than silently write to
  # the first match found.
  def test_ambiguous_intent_across_stores_aborts_with_no_write
    knowdb = File.join(@home, "projects", "knowdb", "store")
    FileUtils.mkdir_p(knowdb)
    write_intent(knowdb, "13--knowdb-collision", id: "13", intent: "Unrelated knowdb thing",
                 sources: [], chain: [])
    write_index(File.join(@home, "projects", "knowdb", "INDEX.md"))
    before = Dir.glob(File.join(@home, "**", "*.md")).to_h { |f| [f, File.read(f)] }

    _out, err = capture_io do
      assert_raises(SystemExit) do
        ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "13").run
      end
    end
    assert_match(/ambiguous/, err)
    assert_match(/--store/, err)

    before.each { |path, original| assert_equal original, File.read(path), "no file may change on an aborted ambiguous run" }
  end

  # The --store companion resolves the SAME ambiguity deliberately.
  def test_explicit_store_disambiguates_and_scopes_correctly
    knowdb = File.join(@home, "projects", "knowdb", "store")
    FileUtils.mkdir_p(knowdb)
    write_intent(knowdb, "13--knowdb-collision", id: "13", intent: "Unrelated knowdb thing",
                 sources: [], chain: [])
    write_index(File.join(@home, "projects", "knowdb", "INDEX.md"))
    knowdb_md = File.join(knowdb, "13--knowdb-collision", "13--knowdb-collision.md")
    before_knowdb = File.read(knowdb_md)

    results = ProjectLinks.new(plastic_home: @home, audit_path: @audit, intent: "13",
                                store: "project:plastic").run

    assert_equal before_knowdb, File.read(knowdb_md),
                 "the non-targeted store's same-id intent must be untouched"
    # Every OTHER store (including knowdb, which also has an id "13") must report a synthetic
    # zero-activity result, never having been handed to project_store at all.
    assert_equal 0, results["project:knowdb"][:entries].size
  end

  # --- ACTION_2 (intent 197): malformed/unresolvable Links line is reported, not silently dropped ---

  def test_unresolvable_link_line_is_reported_not_silently_dropped
    write_intent(File.join(@home, "projects", "plastic", "store"), "20--parent",
                 id: "20", intent: "Parent", sources: [], chain: [],
                 links: "## Links\n- [[does-not-exist-anywhere|Ghost]]\n")

    tool = ProjectLinks.new(plastic_home: @home, audit_path: @audit)
    tool.run

    # The dead line does not survive into the regenerated file (still dropped).
    refute_includes read("projects/plastic/store/20--parent/20--parent.md"), "does-not-exist-anywhere"

    # But it IS reported in the audit as a finding, not silently absent.
    audit = File.read(@audit)
    assert_includes audit, "Malformed references found"
    assert_includes audit, "does-not-exist-anywhere"
  end

  # FALSIFIABLE (208): prove the audit's dead-refs section is not merely ALWAYS empty
  # (which would make the assertion above vacuous). A store with zero dead refs must emit
  # no "Malformed references found" heading at all.
  def test_empty_output_on_nonempty_dead_input_would_be_a_failure
    run_tool
    refute_includes File.read(@audit), "Malformed references found",
      "a clean fixture store must not spuriously report dead refs"
  end

end
