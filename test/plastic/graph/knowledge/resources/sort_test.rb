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

  def preview_lines = Plastic::Graph::Knowledge::Sync::Preview.new(@plastic_home, "global", {}).call

  def setup
    super
    write_old_layout
  end

  def at_new_places = MOVES.values.select { |rel| File.file?(File.join(store_root, INTENT, rel)) }.sort

  def test_rows_move_with_their_files
    sort

    assert_equal %w[resources/output/reports/notes.md resources/output/reports/reviews/r1.md resources/references/ref.md], row_paths("documents").reject { |path| %w[spec.md intent.md].include?(path) }
    assert_equal row_paths("documents"), row_paths("document_heads")
    assert_includes row_paths("printed"), "#{INTENT}/resources/output/reports/reviews/r1.md"
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

  def move_by_hand(from, to)
    FileUtils.mkdir_p(File.dirname(File.join(store_root, INTENT, to)))
    File.rename(File.join(store_root, INTENT, from), File.join(store_root, INTENT, to))
  end

  def test_a_rerun_after_a_partial_sort_completes
    hold_rows("resources/output/reports/reviews/r1.md", OLD_FILES.fetch("reviews/r1.md"))
    move_by_hand("reviews/r1.md", "resources/output/reports/reviews/r1.md")
    sort

    assert_empty Resources::SortPlan.new(folder).moves
    assert_equal "preview: paths that would change: 0", preview_lines.last
  end

  def test_a_second_sort_has_nothing_to_move
    sort

    assert_equal [], sort
  end

  TARGET = "resources/output/reports/reviews/r1.md"

  def hold_same_target
    FileUtils.mkdir_p(File.dirname(File.join(store_root, INTENT, TARGET)))
    File.write(File.join(store_root, INTENT, TARGET), OLD_FILES.fetch("reviews/r1.md"))
    hold_rows(TARGET, OLD_FILES.fetch("reviews/r1.md"))
  end

  def test_a_move_onto_the_same_bytes_deletes_the_source_and_its_rows_and_keeps_the_target
    hold_same_target
    sort

    assert_equal [false, true, true], [File.file?(File.join(store_root, INTENT, "reviews/r1.md")), File.file?(File.join(store_root, INTENT, TARGET)), row_paths("documents").include?(TARGET)]
    refute_includes row_paths("documents"), "reviews/r1.md"
  end

  def test_a_failed_sort_keeps_the_target_a_same_bytes_move_would_have_replaced
    hold_same_target
    before = [files_without_databases, row_digest]

    assert_raises(Errno::EACCES) { sort(rename: failing_on_the_third) }
    assert_equal before, [files_without_databases, row_digest]
  end

  def test_rows_already_at_a_target_stop_the_sort_before_any_file_moves
    hold_rows(TARGET, "other\n")
    before = [files_without_databases, row_digest]

    assert_raises(StandardError) { sort }
    assert_equal before, [files_without_databases, row_digest]
  end

  def failing_on_notes
    folder.tap do |found|
      found.define_singleton_method(:write) do |rel, bytes|
        raise Errno::EIO, rel if rel.end_with?("resources/output/reports/notes.md")

        super(rel, bytes)
      end
    end
  end

  def test_a_failed_link_rewrite_puts_files_rows_and_texts_back
    before = [files_without_databases, row_digest]

    assert_raises(Errno::EIO) { Resources::Sort.new(failing_on_notes, store_graphs).call }
    assert_equal before, [files_without_databases, row_digest]
  end

  def test_a_sort_with_nothing_to_move_still_brings_the_rows_up_to_date
    sort
    File.write(File.join(store_root, INTENT, "spec.md"), "# Spec changed by hand\n")

    refute_empty sort
    assert_equal "preview: paths that would change: 0", preview_lines.last
  end

  def statements_of_a_move_of(count)
    log = []
    spy = Struct.new(:database, :log) do
      def transaction(&) = database.transaction { |batch| yield(batch).tap { log.concat(batch.statements.map(&:sql)) } }
    end
    moves = Array.new(count) { |index| Resources::Move.new("#{INTENT}/old#{index}.md", "#{INTENT}/resources/output/reports/old#{index}.md") }
    Resources::RowMoves.new(spy.new(store_database, log)).call(moves)
    log.grep(/\AUPDATE/)
  end

  def test_the_rows_move_in_one_update_for_each_table
    assert_equal statements_of_a_move_of(2).size, statements_of_a_move_of(40).size
  end
end
