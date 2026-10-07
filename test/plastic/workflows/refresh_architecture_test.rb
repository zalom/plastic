# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/refresh_architecture"

class RefreshArchitectureTest < Plastic::TestCase
  def test_the_agent_is_always_asked_to_refresh_the_map_with_its_own_tool
    outcome, = run_workflow(Plastic::Workflows::RefreshArchitecture)

    assert_match(/the choice of tool is yours/, sole(outcome.steps))
    assert_equal "the agent refreshes the architecture map with its own tool", outcome.because
  end

  def test_the_refresh_names_outcome_md_as_the_record_place
    outcome, = run_workflow(Plastic::Workflows::RefreshArchitecture)

    assert_includes sole(outcome.steps), "under Verification in outcome.md"
    refute_includes sole(outcome.steps), "context you submit"
  end
end
