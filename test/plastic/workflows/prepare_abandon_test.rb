# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/prepare_abandon"

class PrepareAbandonTest < Plastic::TestCase
  include LifecycleHelper

  def prepare = run_workflow(Plastic::Workflows::PrepareAbandon, graphs: Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1"), intent_id: "1")

  def test_a_missing_intent_fails
    assert_kind_of Plastic::Failed, prepare.first
  end

  def test_an_open_intent_without_a_reverted_line_hands_over_the_revert_steps
    open_intent

    assert_equal :reverting, prepare.first
  end
end
