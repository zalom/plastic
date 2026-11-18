# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/park"

class IntentParkTest < Plastic::TestCase
  include AutoHelper

  def park(*args) = plastic("intent", "park", *args, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)

  def log_lines = store_graphs.databases.fetch(:store).rows("SELECT kind, text FROM work_log WHERE intent_id = '1' ORDER BY position").map(&:values)

  def test_an_in_progress_intent_parks_with_its_reason
    active_intent

    result = park("1", "waits", "on", "the", "review")

    assert_call result.with(out: next_line(result)), code: 0, err: "", out: "next: plastic next"
    assert_equal ["parked", "waits on the review"], [status_of("1"), retrieval.intent("1").reason]
  end

  def test_parking_writes_a_work_log_line_with_the_reason
    active_intent

    park("1", "waits on review")

    assert_equal ["parked", "Parked: waits on review"], log_lines.last
  end

  def test_parking_prints_the_parked_status_into_the_index
    active_intent

    park("1", "waits on review")

    assert_equal %w[parked], [listed("1").fetch("status")]
  end

  def test_an_open_intent_exits_1_and_stays_open
    open_intent

    result = park("1", "waits on review")

    assert_equal [1, "open", "plastic: intent 1 is open; only an intent in progress parks\n"], [result.code, status_of("1"), result.err]
  end

  def test_a_future_intent_exits_1_and_stays_future
    open_intent(status: "future")

    result = park("1", "waits on review")

    assert_equal [1, "future"], [result.code, status_of("1")]
  end

  def test_a_parked_intent_exits_1_and_keeps_its_first_reason
    open_intent(status: "parked", reason: "first")

    result = park("1", "second")

    assert_equal [1, "parked", "first"], [result.code, status_of("1"), retrieval.intent("1").reason]
  end

  def test_a_done_intent_exits_1_and_stays_done
    open_intent
    set_status("1", "done")

    assert_equal [1, "done"], [park("1", "late").code, status_of("1")]
  end

  def test_an_abandoned_intent_exits_1_and_stays_abandoned
    open_intent
    set_status("1", "abandoned")

    assert_equal [1, "abandoned"], [park("1", "late").code, status_of("1")]
  end

  def test_no_reason_exits_2_and_parks_nothing
    active_intent

    result = park("1")

    assert_equal [2, "in_progress"], [result.code, status_of("1")]
    assert_includes result.err, "missing"
  end

  def test_a_missing_intent_exits_1
    result = park("9", "gone")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_a_parked_intent_resumes_with_intent_start
    active_intent
    park("1", "waits on review")

    result = start("1")

    assert_equal [0, "in_progress"], [result.code, status_of("1")]
  end
end
