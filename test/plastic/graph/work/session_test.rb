# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkSessionTest < Plastic::TestCase
  def session(**fields) = Plastic::Graph::Work::Session.from_h(session_id: "s-1", last_turn_at: STAMP, **fields)

  def test_a_session_with_an_end_time_has_ended
    assert_predicate session(ended_at: STAMP), :ended?
  end

  def test_a_session_with_a_blank_end_time_has_not_ended
    refute_predicate session(ended_at: ""), :ended?
  end

  UTC = "2026-10-05T08:00:00Z"
  SHOWN = "2026-10-05T17:00:00+09:00"

  def summary(**fields) = session(last_turn_at: UTC, **fields).summary("+09:00")

  def test_an_ended_session_sums_up_as_when_and_why_it_ended_in_the_zone_of_the_machine
    assert_equal "session s-1 ended #{SHOWN} (clear)", summary(ended_at: UTC, end_reason: "clear")
  end

  def test_a_running_session_sums_up_as_its_last_turn_in_the_zone_of_the_machine
    assert_equal "session s-1 last turn #{SHOWN}", summary
  end

  def test_a_session_with_no_turn_sums_up_as_when_it_started_in_the_zone_of_the_machine
    assert_equal "session s-1 started #{SHOWN}, no turn recorded", summary(started_at: UTC, last_turn_at: "")
  end
end
