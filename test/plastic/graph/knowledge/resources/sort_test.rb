# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/sort"
require_relative "../../../../test_helpers/resources_homes"

class ResourcesSortTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Resources = Plastic::Graph::Knowledge::Resources

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def sort(**options) = Resources::Sort.new(folder, store_graphs, **options).call

  REPORT = "resources/output/reports/old.html"

  def record_report
    store_database.transaction do |batch|
      batch.put(:work_log, { intent_id: "1", position: 1, at: STAMP, phase: "", node: "", session_id: "s", kind: "reported", path: REPORT, sha256: "", text: "the old page" })
    end
  end

  def report_at_its_place = File.file?(File.join(store_root, INTENT, REPORT))

  def preview_lines = Plastic::Graph::Knowledge::Sync::Preview.new(@plastic_home, "global", {}).call

  def setup
    super
    write_old_layout
  end

  def at_new_places = MOVES.values.select { |rel| File.file?(File.join(store_root, INTENT, rel)) }.sort

  # No new place of a moved file is one the sync reads by default, so its rows go with the sort.
  def test_the_rows_of_a_file_moved_where_the_sync_does_not_read_go
    sort

    assert_equal [], row_paths("documents").reject { |path| %w[spec.md intent.md].include?(path) }
    assert_equal row_paths("documents"), row_paths("document_heads")
    refute_includes row_paths("printed"), "#{INTENT}/resources/references/ref.md"
  end

  def test_files_move_to_their_destinations
    sort

    assert_equal [MOVES.values.sort, []], [at_new_places, MOVES.keys.select { |rel| File.file?(File.join(store_root, INTENT, rel)) }]
  end

  def test_files_without_a_destination_stay
    sort

    assert_equal %w[delivery.lock plan.md spec.md], intent_files.select { |rel| rel.count("/").zero? && !MOVES.key?(rel) }.sort - %w[graph.json intent.md work.log]
  end

  def test_the_sync_preview_after_the_sort_is_empty
    sort

    assert_equal "preview: paths that would change: 0", preview_lines.last
  end

  def broken_links(dir)
    Dir.glob("**/*.md", base: dir).flat_map { |rel| relative_targets(File.read(File.join(dir, rel))).map { |target| [File.join(dir, rel), target] } }
      .reject { |path, target| target == "missing.md" || File.exist?(File.expand_path(target.sub(/#.*/, ""), File.dirname(path))) }
  end

  def test_the_search_rows_of_the_moved_files_go_with_their_rows
    store_graphs.retrieval.reindex
    fts = -> { store_database.rows("SELECT DISTINCT path FROM document_fts WHERE intent_id = '1' ORDER BY path").map { |row| row.fetch("path") } }
    before = fts.call
    sort

    assert_equal [true, %w[spec.md]], [(HELD - before).empty?, fts.call.reject { |path| path == "intent.md" }]
  end

  def test_every_rewritten_link_resolves
    sort

    assert_empty broken_links(File.join(store_root, INTENT))
  end

  def test_a_failed_rename_rolls_back_rows_and_files
    before = [files_without_databases, row_digest]

    assert_raises(Errno::EACCES) { sort(rename: failing_on_the_third) }
    assert_equal before, [files_without_databases, row_digest]
  end

  def move_by_hand(from, to)
    FileUtils.mkdir_p(File.dirname(File.join(store_root, INTENT, to)))
    File.rename(File.join(store_root, INTENT, from), File.join(store_root, INTENT, to))
  end

  def test_a_rerun_after_a_partial_sort_completes
    hold_rows("resources/tmp/reviews/r1.md", OLD_FILES.fetch("reviews/r1.md"))
    move_by_hand("reviews/r1.md", "resources/tmp/reviews/r1.md")
    sort

    assert_empty Resources::SortPlan.new(folder).moves
    assert_equal "preview: paths that would change: 0", preview_lines.last
  end

  def test_a_report_neither_recorded_nor_mandatory_is_named_and_moved_to_tmp
    write("#{INTENT}/#{REPORT}", "<p>old</p>\n")
    lines = sort

    assert_includes lines, "moved #{INTENT}/#{REPORT} to #{INTENT}/resources/tmp/old.html: neither recorded nor mandatory"
    assert_equal [false, true], [report_at_its_place, File.file?(File.join(store_root, INTENT, "resources/tmp/old.html"))]
  end

  def test_a_recorded_report_stays
    write("#{INTENT}/#{REPORT}", "<p>old</p>\n")
    record_report
    sort

    assert report_at_its_place
  end

  def test_a_mandatory_report_stays
    write("#{INTENT}/#{REPORT}", "<p>old</p>\n")
    sort(reports: Plastic::Graph::Knowledge::Reports.new(mandatory: %w[old.html]))

    assert report_at_its_place
  end

  def test_a_second_sort_has_nothing_to_move
    sort

    assert_equal [], sort
  end
end
