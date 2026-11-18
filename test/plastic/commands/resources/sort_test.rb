# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/resources_homes"
require_relative "../../../../lib/plastic/commands/resources/sort"

class ResourcesSortCommandTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  def setup
    super
    write_old_layout
  end

  def sort(*args) = plastic("resources", "sort", "--store", "global", *args, table: Plastic::CLI::TABLE)

  def test_the_preview_lists_the_links_that_would_change_and_the_links_left_alone
    out = sort("--dry-run").out

    assert_includes out, "preview: link would change #{INTENT}/spec.md: reviews/r1.md -> resources/output/reports/reviews/r1.md"
    assert_includes out, "preview: link left as it is #{INTENT}/resources/notes.md: missing.md"
  end

  def test_the_real_run_prints_the_links_it_changed_and_the_links_it_left_alone
    out = sort.out

    assert_includes out, "link changed #{INTENT}/spec.md: reviews/r1.md -> resources/output/reports/reviews/r1.md"
    assert_includes out, "link left as it is #{INTENT}/resources/notes.md: missing.md"
  end

  def test_a_second_run_says_there_is_nothing_to_move
    sort

    assert_includes sort.out, "sorted: nothing to move"
  end
end
