# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/abandon_intent"

class AbandonIntentTest < Plastic::TestCase
  def abandon = run_workflow(Plastic::Workflows::AbandonIntent, graphs: session_graphs, intent_id: "1")

  def session_graphs = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1")

  def test_an_intent_with_an_outcome_is_abandoned_and_named
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped.\n\n## Verification\n- Reverted: nothing delivered\n")
    sync_up

    outcome, context = abandon

    assert_equal [:done, ["intent: 1 abandoned"]], [outcome, context.printed]
    assert_equal "abandoned", retrieval.intent("1").status
  end

  def test_a_stale_done_fact_still_abandons
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped.\n")
    sync_up

    run_workflow(Plastic::Workflows::AbandonIntent, graphs: session_graphs, intent_id: "1", abandon_ended: true)

    assert_equal "abandoned", retrieval.intent("1").status
  end

  def test_an_intent_without_an_outcome_fails
    open_intent

    assert_kind_of Plastic::Failed, abandon.first
  end
  def test_an_abandon_with_no_supersedes_link_is_cancelled
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped.\n\n## Verification\n- Reverted: nothing delivered\n")
    sync_up
    abandon

    assert_equal "cancelled", retrieval.intent("1").disposition
  end
end
