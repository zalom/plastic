# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/registry"
require_relative "../../../lib/plastic/workflows/agent/intent/end"
require_relative "../../../lib/plastic/workflows/agent/intent/end/check_merge"
require_relative "../../../lib/plastic/workflows/agent/shared/wind_down_intent"

class UnreachableEndingsTest < Minitest::Test
  Facts = Struct.new(:requirements, :judged, :merge_recorded, :map_recorded, keyword_init: true)

  FINISH = Plastic::Workflows::Agent::Intent::End
  CHECK_MERGE = Plastic::Workflows::Agent::Intent::End::CheckMerge
  WIND_DOWN = Plastic::Workflows::Agent::Shared::WindDownIntent

  def left(workflow, facts) = workflow.steps.select { |step| step.left?(facts) }

  def done_outcome(workflow) = workflow.outcomes.find { |each| each.name == :done }

  def test_the_done_ending_of_finishing_the_records_is_marked_unreachable
    assert done_outcome(FINISH).unreachable
  end

  def test_a_step_is_left_whenever_the_records_or_the_verdict_are_missing_which_is_the_only_way_into_finishing_the_records
    [Facts.new(requirements: ["a record"], judged: true), Facts.new(requirements: [], judged: false), Facts.new(requirements: ["a record"], judged: false)].each do |facts|
      refute_empty left(FINISH, facts)
    end
  end

  def test_the_done_ending_of_checking_the_merge_is_marked_unreachable
    assert done_outcome(CHECK_MERGE).unreachable
  end

  def test_a_step_is_left_whenever_the_merge_or_the_map_is_not_recorded_which_is_the_only_way_into_checking_the_merge
    [[true, false], [false, true], [false, false]].each do |merge, map|
      refute_empty left(CHECK_MERGE, Facts.new(merge_recorded: merge, map_recorded: map))
    end
  end

  def test_the_done_ending_of_winding_down_is_marked_unreachable
    assert done_outcome(WIND_DOWN).unreachable
  end

  def test_the_step_of_winding_down_is_never_done
    refute_empty left(WIND_DOWN, Facts.new)
  end

  def test_an_outcome_reachable_by_default_is_not_marked
    assert_nil Plastic::Workflows::Agent::Intent::End.outcomes.find { |each| each.name == :handoff }.unreachable
  end
end
