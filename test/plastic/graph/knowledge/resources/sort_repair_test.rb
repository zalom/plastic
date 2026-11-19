# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/sort"
require_relative "../../../../test_helpers/resources_homes"

class ResourcesSortRepairTest < Plastic::TestCase
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

  TARGET = "resources/tmp/reviews/r1.md"

  def hold_same_target
    FileUtils.mkdir_p(File.dirname(File.join(store_root, INTENT, TARGET)))
    File.write(File.join(store_root, INTENT, TARGET), OLD_FILES.fetch("reviews/r1.md"))
    hold_rows(TARGET, OLD_FILES.fetch("reviews/r1.md"))
  end

  def test_a_move_onto_the_same_bytes_deletes_the_source_and_its_rows_and_keeps_the_target_file
    hold_same_target
    sort

    assert_equal [false, true], [File.file?(File.join(store_root, INTENT, "reviews/r1.md")), File.file?(File.join(store_root, INTENT, TARGET))]
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
    failures = [Errno::EIO]
    folder.tap do |found|
      found.define_singleton_method(:write) do |rel, bytes|
        raise failures.shift, rel if rel.end_with?("resources/tmp/notes.md") && failures.any?

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
