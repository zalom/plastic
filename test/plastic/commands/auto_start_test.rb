# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto_start"

class AutoStartTest < Plastic::TestCase
  def call(*args, env: {}) = plastic("auto", "start", *args, env: { "PLASTIC_SESSION" => "s-1" }.merge(env), table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def test_an_open_decision_refuses_and_the_status_stays_open
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_equal 3, result.code
    assert_equal "open", store_graphs.retrieval.intent(intent.intent_id).status
  end

  def test_no_done_criteria_refuses
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- none\n")

    result = call(intent.intent_id)

    assert_equal 3, result.code
  end

  def test_another_sessions_live_lock_refuses
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n")
    store_graphs.work.take_lock(intent.intent_id, session_id: "s-2", mode: "auto")

    result = call(intent.intent_id)

    assert_equal 3, result.code
  end

  def test_a_call_with_no_session_fails
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n")

    result = call(intent.intent_id, env: { "PLASTIC_SESSION" => "" })

    assert_equal 1, result.code
  end

  def test_a_clear_spec_goes_active
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n")

    result = call(intent.intent_id)

    assert_equal 0, result.code
    assert_equal "active", store_graphs.retrieval.intent(intent.intent_id).status
    assert_includes result.out, "next: plastic intent brief #{intent.intent_id}"
  end

  def test_a_clear_spec_takes_the_lock
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n")

    call(intent.intent_id)

    assert_equal "s-1", store_graphs.retrieval.lock(intent.intent_id).session_id
  end

  def test_a_missing_intent_refuses
    result = call("9")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_a_done_intent_refuses
    open_intent
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :intent_id", intent_id: "1")
    end

    result = call("1")

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 is done"
  end
end
