# frozen_string_literal: true

require_relative "../../test_helper"

class GraphRecordTest < Plastic::TestCase
  Pair = Data.define(:left, :right) { include Plastic::Graph::Record }

  def test_a_row_with_string_keys_builds_the_record
    assert_equal Pair.new("a", "b"), Pair.from_h({ "left" => "a", "right" => "b" })
  end

  def test_a_key_the_record_does_not_have_is_dropped
    assert_equal Pair.new("a", "b"), Pair.from_h({ left: "a", right: "b", extra: "c" })
  end

  def test_a_missing_key_reads_as_nil
    assert_equal Pair.new("a", nil), Pair.from_h({ left: "a" })
  end
end
