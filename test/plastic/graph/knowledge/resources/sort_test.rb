# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../test_helpers/resources_homes"

class ResourcesSortTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Resources = Plastic::Graph::Knowledge::Resources

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def sort(**options) = Resources::Sort.new(folder, store_graphs, **options).call

  def preview_lines = Plastic::Graph::Knowledge::Sync::Preview.new(@plastic_home, "global", {}).call

  def setup
    super
    write_old_layout
  end

  def at_new_places = MOVES.values.select { |rel| File.file?(File.join(store_root, INTENT, rel)) }.sort

  def test_rows_move_with_their_files
    sort

    assert_equal %w[resources/output/reports/notes.md resources/output/reports/reviews/r1.md resources/references/ref.md], row_paths("documents").reject { |path| path == "spec.md" }
    assert_equal row_paths("documents"), row_paths("document_heads")
    assert_includes row_paths("printed"), "#{INTENT}/resources/output/reports/reviews/r1.md"
  end

  def test_files_move_to_their_destinations
    sort

    assert_equal [MOVES.values.sort, []], [at_new_places, MOVES.keys.select { |rel| File.file?(File.join(store_root, INTENT, rel)) }]
  end

  def test_files_without_a_destination_stay
    sort

    assert_equal %w[delivery.lock plan.md spec.md], intent_files.select { |rel| rel.count("/").zero? && !MOVES.key?(rel) }.sort
  end

  def test_the_sync_preview_after_the_sort_is_empty
    sort

    assert_equal ["preview: paths that would change: 0"], preview_lines
  end

  def broken_links(dir)
    Dir.glob("**/*.md", base: dir).flat_map { |rel| relative_targets(File.read(File.join(dir, rel))).map { |target| [File.join(dir, rel), target] } }
      .reject { |path, target| target == "missing.md" || File.exist?(File.expand_path(target.sub(/#.*/, ""), File.dirname(path))) }
  end

  def test_every_rewritten_link_resolves
    sort

    assert_empty broken_links(File.join(store_root, INTENT))
  end

  def files_without_databases = snapshot(store_root).reject { |rel, _| rel.match?(/\.db(-wal|-shm|-journal)?\z/) }

  def failing_on_the_third
    calls = 0
    lambda do |from, to|
      calls += 1
      raise Errno::EACCES, to if calls == 3

      File.rename(from, to)
    end
  end

  def test_a_failed_rename_rolls_back_rows_and_files
    before = [files_without_databases, row_digest]

    assert_raises(Errno::EACCES) { sort(rename: failing_on_the_third) }
    assert_equal before, [files_without_databases, row_digest]
  end

  def test_a_rerun_after_a_partial_sort_completes
    hold_rows("resources/output/reports/reviews/r1.md", OLD_FILES.fetch("reviews/r1.md"))
    FileUtils.mkdir_p(File.join(store_root, INTENT, "resources/output/reports/reviews"))
    File.rename(File.join(store_root, INTENT, "reviews/r1.md"), File.join(store_root, INTENT, "resources/output/reports/reviews/r1.md"))
    sort

    assert_empty Resources::SortPlan.new(folder).moves
    assert_equal ["preview: paths that would change: 0"], preview_lines
  end

  def test_a_second_sort_has_nothing_to_move
    sort

    assert_equal [], sort
  end
end
