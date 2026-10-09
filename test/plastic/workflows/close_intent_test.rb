# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/close_intent"

class CloseIntentTest < Plastic::TestCase
  include DeliveryHelper

  def ready = ready_intent

  def close = run_workflow(Plastic::Workflows::CloseIntent, graphs: session_graphs, intent_id: "1")

  def test_a_ready_intent_is_closed_and_named
    ready

    outcome, context = close

    assert_equal :done, outcome
    assert_includes context.printed, "intent: 1 done"
    assert_includes context.printed.join("\n"), "graph.json"
    assert_equal "done", retrieval.intent("1").status
  end

  def test_the_close_writes_the_verdict_judge_and_chains_to_the_wind_down_step
    ready

    _, context = close

    assert_equal "verdict", retrieval.completion("1").fetch("judge")
    assert_includes Plastic::Workflows::CloseIntent.chain.keys + context.printed, :agent_wind_down_intent
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
