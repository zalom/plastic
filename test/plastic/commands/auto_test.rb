# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto"

class AutoTest < Plastic::TestCase
  include RoadmapHelper
  include AutoHelper

  def test_a_clear_spec_goes_active_and_takes_the_lock
    intent = clear_intent

    id = intent.intent_id

    result = call(id)

    assert_equal [0, "active", %w[s-1 auto]], [result.code, retrieval.intent(id).status, retrieval.lock(id).to_h.values_at(:session_id, :mode)]
    assert_includes result.out, "next: plastic intent brief #{id}"
    assert_empty result.err
  end

  def test_an_open_decision_refuses_and_the_status_stays_open
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_equal [3, "open"], [result.code, retrieval.intent(intent.intent_id).status]
    assert_includes result.err, "intent 1 has an open decision; run plastic intent spec 1"
  end

  def test_no_done_criteria_exits_1_and_offers_the_spec
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- none\n")

    result = call(intent.intent_id)

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 names no done criterion"
    assert_match(/^next: plastic intent spec 1/, result.out)
  end

  def test_another_sessions_live_lock_refuses_and_is_kept
    intent = clear_intent
    store_graphs.work.take_lock(intent.intent_id, session_id: "s-2", mode: "auto")

    result = call(intent.intent_id)

    assert_equal [3, "s-2"], [result.code, retrieval.lock(intent.intent_id).session_id]
    assert_includes result.err, "intent 1 is locked by session s-2"
  end

  def test_a_done_intent_exits_1_and_offers_plastic_next
    open_intent
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :intent_id", intent_id: "1")
    end

    result = call("1")

    assert_equal 1, result.code
    assert_includes result.err, "intent 1 is done"
    assert_match(/^next: plastic next/, result.out)
  end

  def test_an_intent_with_a_criterion_and_no_go_ahead_still_exits_3
    intent = open_intent
    write_spec(intent, CLEAR_SPEC)

    result = call(intent.intent_id)

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 has no go-ahead"
  end

  def test_a_call_with_no_session_fails
    intent = clear_intent

    result = call(intent.intent_id, env: { "PLASTIC_SESSION" => "" })

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "plastic auto names no session"
  end

  def test_two_ids_exit_2_and_write_no_lock
    clear_intent
    write_spec(open_intent("Beta"), CLEAR_SPEC)

    result = call("1", "2")

    assert_equal [2, [], %w[open open]], [result.code, lock_rows, %w[1 2].map { |id| retrieval.intent(id).status }]
    assert_includes result.err, "unexpected 2"
  end

  def test_no_id_exits_2
    result = call

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "missing"
  end

  def test_a_missing_intent_fails
    result = call("9")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_an_active_intent_without_a_lock_takes_one
    intent = active_intent

    result = call(intent.intent_id)

    lock = retrieval.lock(intent.intent_id)

    assert_equal [0, "s-1", "auto", true], [result.code, lock&.session_id, lock&.mode, lock&.live?]
  end

  def test_an_expired_foreign_lock_is_taken_over
    intent = active_intent
    store_graphs.work.take_lock(intent.intent_id, session_id: "s-2", mode: "auto")
    expire_lock

    result = call(intent.intent_id)

    lock = retrieval.lock(intent.intent_id)

    assert_equal [0, "s-1", true], [result.code, lock.session_id, lock.live?]
  end
end
