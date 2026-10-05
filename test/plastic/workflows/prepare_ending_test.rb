# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/prepare_ending"

class PrepareEndingTest < Plastic::TestCase
  include DeliveryHelper

  def prepare(session: "s-1", judge: nil, evidence: nil)
    run_workflow(Plastic::Workflows::PrepareEnding, harness: scoped_harness(session:), graphs: session_graphs, intent_id: "1", judge:, evidence:)
  end

  def evidence_file(intent, body = { "It works" => "the tests pass" })
    write("#{intent.dir}/completion.json", JSON.generate(body))
    "completion.json"
  end

  def test_a_ready_intent_with_its_evidence_is_ready_to_end
    intent = ready_intent

    outcome, context = prepare(judge: "tests", evidence: evidence_file(intent))

    assert_equal [:ready, { "It works" => "the tests pass" }], [outcome, context.attestation]
  end

  def test_an_intent_without_evidence_needs_the_agent_with_an_example
    ready_intent

    outcome, context = prepare

    assert_equal [:agent_needed, { "It works" => "Describe the evidence for this criterion" }], [outcome, JSON.parse(context.evidence_example)]
  end

  def test_evidence_that_misses_a_criterion_fails_the_call
    intent = ready_intent

    outcome, = prepare(judge: "tests", evidence: evidence_file(intent, { "Other" => "text" }))

    assert_equal "code_prepare_ending, gate: evidence must map every exact done criterion to nonempty evidence text", outcome.message
  end

  def test_an_unknown_judge_fails_the_call
    ready_intent

    assert_equal "code_prepare_ending, gate: --judge takes tests, tool, agent or owner", prepare(judge: "luck", evidence: "x").first.message
  end

  def test_a_done_intent_is_already_closed
    open_intent(status: "done")

    assert_equal :closed, prepare.first
  end

  def test_another_live_session_lock_is_refused
    ready_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    outcome, = prepare

    assert_equal [Plastic::Refused, "intent 1 is locked by session s-2"], [outcome.class, outcome.message]
  end

  def test_an_abandoned_intent_fails_the_call
    open_intent(status: "abandoned")

    assert_equal "code_prepare_ending, gate: intent 1 is not open or active", prepare.first.message
  end
end
