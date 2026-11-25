# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/repair/rebuild/generated"

# A placeholder or a generated stub holds no data.
class RebuildGeneratedTest < Minitest::Test
  Generated = Plastic::Graph::Knowledge::Repair::Rebuild::Generated

  def test_the_placeholder_marker_is_generated
    assert Generated.call("<!-- plastic:placeholder -->\n# Plan: x\n")
  end

  def test_the_backfill_marker_is_generated
    assert Generated.call("# Plan: x\n<!-- backfilled from the record by end-intent on 2026-09-02T12:20:52Z -->\n")
  end

  def test_an_empty_file_is_generated
    assert Generated.call("\n")
  end

  def test_a_plan_with_words_is_not_generated
    refute Generated.call("# Plan\n\n1. Search.\n")
  end

  def test_a_marker_quoted_below_the_top_does_not_make_a_filled_file_generated
    refute Generated.call("# Plan\n\nReal work.\n\nThe stub says `<!-- plastic:placeholder -->` and `backfilled from the record by end-intent`.\n")
  end
end
