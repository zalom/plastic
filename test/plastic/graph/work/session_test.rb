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

  def test_an_ended_session_sums_up_as_when_and_why_it_ended
    assert_equal "session s-1 ended #{STAMP} (clear)", session(ended_at: STAMP, end_reason: "clear").summary
  end

  def test_a_running_session_sums_up_as_its_last_turn
    assert_equal "session s-1 last turn #{STAMP}", session.summary
  end

  def test_a_session_with_no_turn_sums_up_as_when_it_started
    assert_equal "session s-1 started #{STAMP}, no turn recorded", session(started_at: STAMP, last_turn_at: "").summary
  end
end
