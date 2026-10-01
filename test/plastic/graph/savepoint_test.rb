# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/graph/savepoint"

class SavepointTest < Plastic::TestCase
  Savepoint = Plastic::Graph::Savepoint
  AT = "2026-10-01T10:00:00+02:00"

  def test_a_timed_line_splits_into_its_time_and_its_text
    assert_equal [AT, "Spec written"], Savepoint.parse("#{AT}  Spec written")
  end

  def test_a_line_with_no_time_keeps_its_text
    assert_equal [nil, "free text"], Savepoint.parse("free text")
  end

  def test_a_line_prints_its_time_only_when_it_has_one
    assert_equal ["#{AT}  a", "b"], [Savepoint.new("1", 1, AT, "a", "o").line, Savepoint.new("1", 2, nil, "b", "o").line]
  end
end
