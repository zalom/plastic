# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/prepare_ending"

class PrepareEndingFixture < Plastic::TestCase
  include DeliveryHelper

  KEYED = "## Done criteria\n- [ ] [works] It works\n"

  def prepare(session: "s-1", judge: nil, evidence: nil, abandoned: false)
    run_workflow(Plastic::Workflows::PrepareEnding, harness: scoped_harness(session:), graphs: session_graphs, intent_id: "1", judge:, evidence:, abandoned:)
  end

  def evidence_file(intent, body = { "It works" => "the tests pass" })
    write("#{intent.dir}/completion.json", JSON.generate(body))
    "completion.json"
  end
end

class PrepareEndingTest < PrepareEndingFixture
  def test_a_ready_intent_with_its_evidence_is_ready_to_end
    intent = ready_intent

    outcome, context = prepare(judge: "tests", evidence: evidence_file(intent))

    assert_equal [:ready, { "It works" => "the tests pass" }], [outcome, context.attestation]
  end

  def test_keyed_evidence_is_ready
    intent = ready_intent(spec: KEYED)

    assert_equal :ready, prepare(judge: "tests", evidence: evidence_file(intent, { "works" => "ok" })).first
  end

  def test_an_intent_without_evidence_needs_the_agent_with_an_example
    ready_intent

    outcome, context = prepare

    assert_equal [:agent_needed, { "It works" => "Describe the evidence for this criterion" }], [outcome, JSON.parse(context.evidence_example)]
  end

  def test_the_example_is_keyed_by_the_criterion_keys
    ready_intent(spec: KEYED)

    assert_equal({ "works" => "Describe the evidence for this criterion" }, JSON.parse(prepare.last.evidence_example))
  end

  def test_evidence_that_misses_a_criterion_fails_the_call
    intent = ready_intent

    outcome, = prepare(judge: "tests", evidence: evidence_file(intent, { "Other" => "text" }))

    assert_includes outcome.message, "code_prepare_ending, gate: evidence must map every criterion key"
  end

  def test_evidence_by_text_for_a_keyed_criterion_fails_the_call
    intent = ready_intent(spec: KEYED)

    outcome, = prepare(judge: "tests", evidence: evidence_file(intent, { "It works" => "text" }))

    assert_includes outcome.message, "missing keys: works"
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

  def test_an_abandoned_intent_fails_the_delivered_call
    open_intent(status: "abandoned")

    assert_equal "code_prepare_ending, gate: intent 1 is not open or active", prepare.first.message
  end
end

class PrepareEndingVerificationTest < PrepareEndingFixture
  def test_evidence_without_the_verification_records_is_unverified
    intent = ready_intent(verification: "")

    outcome, = prepare(judge: "tests", evidence: evidence_file(intent))

    assert_equal :unverified, outcome
  end

  def test_a_bare_call_without_the_verification_records_is_unverified
    ready_intent(verification: "")

    outcome, context = prepare

    assert_equal [:unverified, false, false], [outcome, context.merge_recorded, context.map_recorded]
  end

  def test_requirements_hold_only_the_record_problems
    ready_intent(verification: "")

    assert_empty prepare.last.requirements
  end

  def test_missing_records_come_before_the_merge_check
    specified_intent

    outcome, context = prepare

    assert_equal :agent_needed, outcome
    refute_empty context.requirements
  end
end

class PrepareEndingAbandonTest < PrepareEndingFixture
  def droppable(**fields)
    intent = open_intent("Alpha", **fields)
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped: the need went away.\n")
    sync_up
  end

  def test_an_open_intent_without_criteria_or_nodes_routes_to_the_abandon
    droppable

    assert_equal [:abandoning, nil], [prepare(abandoned: true).first, prepare(abandoned: true).last.problem]
  end

  def test_a_future_intent_can_be_abandoned
    droppable(status: "future")

    assert_equal :abandoning, prepare(abandoned: true).first
  end

  def test_a_parked_intent_can_be_abandoned
    droppable(status: "parked")

    assert_equal :abandoning, prepare(abandoned: true).first
  end

  def test_a_done_intent_cannot_be_abandoned
    droppable(status: "done")

    assert_includes prepare(abandoned: true).first.message, "gate:"
  end

  def test_abandoning_an_abandoned_intent_routes_to_the_abandon
    open_intent(status: "abandoned")

    assert_equal :abandoning, prepare(abandoned: true).first
  end

  def test_abandoning_a_foreign_locked_intent_is_refused
    droppable
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    assert_kind_of Plastic::Refused, prepare(abandoned: true).first
  end

  def test_an_abandon_without_a_substantive_outcome_fails_the_call
    open_intent

    assert_includes prepare(abandoned: true).first.message, "outcome.md"
  end
end
