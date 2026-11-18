# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/workflows/code/intent/abandon/prepare"

class PrepareAbandonTest < Plastic::TestCase
  include LifecycleHelper

  def prepare = run_workflow(Plastic::Workflows::Code::Intent::Abandon::Prepare, graphs: Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1"), intent_id: "1")

  def test_a_missing_intent_fails
    assert_raises(Plastic::Failed) { prepare }
  end

  def test_a_started_intent_without_a_reverted_line_hands_over_the_revert_steps
    open_intent(status: "in_progress")

    assert_equal :reverting, prepare.first
  end

  def test_an_open_intent_with_no_node_and_no_reverted_line_is_abandoned
    open_intent

    assert_equal :abandoning, prepare.first
  end
end
