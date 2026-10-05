# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/close_intent"

class CloseIntentTest < Plastic::TestCase
  include DeliveryHelper

  EVIDENCE = { "It works" => "the tests pass" }.freeze

  def ready = ready_intent

  def close = run_workflow(Plastic::Workflows::CloseIntent, graphs: session_graphs, intent_id: "1", judge: "agent", attestation: EVIDENCE)

  def test_a_ready_intent_is_closed_and_named
    ready

    outcome, context = close

    assert_equal [:done, ["intent: 1 done"]], [outcome, context.printed]
    assert_equal "done", retrieval.intent("1").status
  end

  def test_closing_rewrites_the_index
    ready
    close

    assert_includes File.read(store_path("store/index.json")), "\"done\""
  end

  def test_an_intent_with_problems_fails_with_no_completion
    open_intent

    outcome, = close

    assert_kind_of Plastic::Failed, outcome
    assert_nil retrieval.completion("1")
  end
end
