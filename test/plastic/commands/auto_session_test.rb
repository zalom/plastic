# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/auto"

class AutoSessionTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def ended_session_intent
    intent = clear_intent
    store_graphs.work.open_session("s-1", harness: "claude-code", directory: @home)
    store_graphs.work.end_session("s-1", reason: "clear")
    intent
  end

  def test_a_session_that_ended_exits_1_and_names_the_session
    result = call(ended_session_intent.intent_id)

    assert_equal 1, result.code
    assert_includes result.err, "session s-1 ended; start a new session or resume it"
  end

  def test_a_session_that_ended_offers_no_next_command
    refute_match(/^next: /, call(ended_session_intent.intent_id).out)
  end

  def test_a_session_that_ended_leaves_the_intent_open_with_no_lock
    intent = ended_session_intent
    call(intent.intent_id)

    assert_equal ["open", []], [retrieval.intent(intent.intent_id).status, lock_rows]
  end

  def test_a_session_reopened_after_its_end_locks_the_intent
    intent = ended_session_intent
    store_graphs.work.open_session("s-1", harness: "claude-code", directory: @home)

    result = call(intent.intent_id)

    assert_equal [0, "s-1", true], [result.code, *held_lock(intent.intent_id)]
  end
end
