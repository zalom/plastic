# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/end"
require "plastic/commands/intent/end"

class CloseIntentTest < Plastic::TestCase
  include DeliveryHelper

  def ready = ready_intent.tap { store_graphs.work.add_verdict(intent_id: "1", verdict: "accept", findings: "Checked against the spec") }

  def close = run_workflow(Plastic::Workflows::Code::Intent::End, graphs: session_graphs, intent_id: "1")

  def test_a_ready_intent_is_closed_and_named
    ready

    outcome, context = close

    assert_equal :done, outcome
    assert_includes context.printed.join("\n"), "intent: 1 done"
    assert_equal "done", retrieval.intent("1").status
  end

  def test_the_close_writes_the_verdict_judge_and_chains_to_the_wind_down_step
    ready

    close

    assert_equal "verdict", structure.completions("1").first.judge
    assert_includes Plastic::Commands::Intent::End.chain.keys, :agent_wind_down_intent
  end

  def test_an_intent_with_problems_fails_with_no_completion
    open_intent

    assert_raises(Plastic::Failed) { close }
    assert_nil structure.completions("1").first
  end

  def drive(session) = session_graphs(session).work.drive_intent(intent_id: "1", by: session)

  def drivers = store_graphs.databases.fetch(:store).rows("SELECT session_id FROM drivers")

  def test_the_close_releases_the_driver_claim_of_the_intent
    ready
    drive("s-1")

    close

    assert_empty drivers
  end

  def test_the_close_says_which_session_held_the_driver_claim
    ready
    drive("s-1")

    _, context = close

    assert_includes context.printed, "driver claim: released, held by session s-1"
  end

  def test_a_close_with_no_driver_claim_prints_no_release_line
    ready

    _, context = close

    assert_equal ["intent: 1 done"], context.printed
  end
end
