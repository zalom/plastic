# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/resources_homes"
require_relative "../../../../lib/plastic/commands/resources/sort"

class ResourcesSortCommandTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  def sort(*args) = plastic("resources", "sort", *args, table: Plastic::CLI::TABLE)

  def setup
    super
    write_old_layout
  end

  def files_without_databases = snapshot(store_root).reject { |rel, _| rel.match?(/\.db(-wal|-shm|-journal)?\z/) }

  def test_dry_run_writes_nothing
    before = [files_without_databases, row_digest]
    result = sort("--store", "global", "--dry-run")

    assert_equal 0, result.code
    assert_includes result.out, "preview: move #{INTENT}/reviews/r1.md -> #{INTENT}/resources/output/reports/reviews/r1.md"
    assert_equal before, [files_without_databases, row_digest]
  end

  def test_a_run_moves_the_files_and_says_how_many
    result = sort("--store", "global")

    assert_equal 0, result.code
    assert_includes result.out, "sorted: #{MOVES.size} files moved"
    assert_includes intent_files, "resources/output/reports/reviews/r1.md"
  end

  def test_a_sorted_store_says_so
    sort("--store", "global")

    assert_includes sort("--store", "global").out, "sorted: nothing to move"
  end

  def test_unknown_store_is_usage
    result = sort("--store", "nowhere")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "nowhere"
  end

  def test_a_call_without_store_is_usage
    assert_equal 2, sort.code
  end
end
