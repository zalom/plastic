# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkSessionTouchedTest < Plastic::TestCase
  def latest_first(*rows) = Plastic::Graph::Work::Session::Touched.latest_first(rows.map { |at, id| { "at" => at, "intent_id" => id } })

  def test_the_intents_come_most_recent_first_and_once_each
    assert_equal %w[2 1], latest_first(["2026-10-01", "1"], ["2026-10-03", "2"], ["2026-10-02", "1"])
  end

  def test_a_row_with_no_intent_is_left_out
    assert_equal %w[1], latest_first(["2026-10-01", "1"], ["2026-10-02", nil])
  end
end
