# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/agent/architecture/refresh"

class RefreshArchitectureTest < Plastic::TestCase
  def test_the_agent_is_always_asked_to_refresh_the_map_with_its_own_tool
    outcome, = run_workflow(Plastic::Workflows::Agent::Architecture::Refresh)

    assert_match(/the choice of tool is yours/, sole(outcome.steps))
    assert_equal "the agent refreshes the architecture map with its own tool", outcome.because
  end

  def test_the_refresh_asks_for_no_record_in_outcome_md
    outcome, = run_workflow(Plastic::Workflows::Agent::Architecture::Refresh)

    refute_includes sole(outcome.steps), "outcome.md"
    refute_includes sole(outcome.steps), "Architecture map:"
  end

  def test_the_refresh_ties_the_map_to_planning_code_work
    outcome, = run_workflow(Plastic::Workflows::Agent::Architecture::Refresh)

    assert_includes sole(outcome.steps), "before you plan code work"
  end
end
