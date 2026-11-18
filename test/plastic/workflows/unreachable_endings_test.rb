# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/registry"
require_relative "../../../lib/plastic/workflows/agent/intent/end"
require_relative "../../../lib/plastic/workflows/agent/intent/end/check_delivery"
require_relative "../../../lib/plastic/workflows/agent/shared/wind_down_intent"
require_relative "../../../lib/plastic/workflows/code/intent/end"
require_relative "../../../lib/plastic/workflows/code/intent/end/prepare"

# Each agent workflow of intent end is entered by an edge of the chain whose condition leaves a step of the workflow to do, so its done ending cannot be reached.
class UnreachableEndingsTest < Minitest::Test
  Facts = Struct.new(:requirements, :judged, :delivery_recorded, :map_recorded)

  FINISH = Plastic::Workflows::Agent::Intent::End
  CHECK_DELIVERY = Plastic::Workflows::Agent::Intent::End::CheckDelivery
  WIND_DOWN = Plastic::Workflows::Agent::Shared::WindDownIntent
  PREPARE = Plastic::Workflows::Code::Intent::End::Prepare
  CLOSE = Plastic::Workflows::Code::Intent::End

  def left(workflow, facts) = workflow.steps.select { |step| step.left?(facts) }

  def outcome(workflow, name) = workflow.outcomes.find { |each| each.name == name }

  def entered(name, facts) = outcome(PREPARE, name).holds?(facts)

  def finishing_facts = [{ requirements: ["a record"], judged: true }, { requirements: [], judged: false }, { requirements: ["a record"], judged: false }].map { |each| Facts.new(**each) }

  def delivery_facts = [[true, false], [false, true], [false, false]].map { |delivery, map| Facts.new(requirements: [], judged: true, delivery_recorded: delivery, map_recorded: map) }

  def test_the_done_ending_of_finishing_the_records_is_marked_unreachable
    assert outcome(FINISH, :done).unreachable
  end

  def test_the_edge_into_finishing_the_records_holds_only_while_a_step_of_it_is_left
    finishing_facts.each do |facts|
      assert entered(:agent_needed, facts)
      refute_empty left(FINISH, facts)
    end
  end

  def test_the_edge_into_finishing_the_records_does_not_hold_once_no_step_of_it_is_left
    facts = Facts.new(requirements: [], judged: true)

    refute entered(:agent_needed, facts)
    assert_empty left(FINISH, facts)
  end

  def test_the_done_ending_of_checking_the_delivery_is_marked_unreachable
    assert outcome(CHECK_DELIVERY, :done).unreachable
  end

  def test_the_edge_into_checking_the_delivery_holds_only_while_a_step_of_it_is_left
    delivery_facts.each do |facts|
      assert entered(:unverified, facts)
      refute_empty left(CHECK_DELIVERY, facts)
    end
  end

  def test_the_edge_into_checking_the_delivery_does_not_hold_once_no_step_of_it_is_left
    facts = Facts.new(requirements: [], judged: true, delivery_recorded: true, map_recorded: true)

    refute entered(:unverified, facts)
    assert_empty left(CHECK_DELIVERY, facts)
  end

  def test_the_done_ending_of_winding_down_is_marked_unreachable
    assert outcome(WIND_DOWN, :done).unreachable
  end

  def test_the_edge_into_winding_down_always_holds_and_the_step_of_it_is_never_done
    assert outcome(CLOSE, :done).holds?(Facts.new)
    refute_empty left(WIND_DOWN, Facts.new)
  end

  def test_an_outcome_reachable_by_default_is_not_marked
    assert_nil outcome(FINISH, :handoff).unreachable
  end
end
