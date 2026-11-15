# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../support/second_load"
require_relative "../../../../../lib/plastic/workflows/code/roadmap/roadmap_workflow"
%w[check drop log next show].each { |name| require_relative "../../../../../lib/plastic/workflows/code/roadmap/#{name}" }

class RoadmapWorkflowTest < Plastic::TestCase
  Roadmap = Plastic::Workflows::Code::Roadmap
  GATE = "Gate:no roadmap %{slug}"
  STEPS = {
    Roadmap::Check => [GATE, "Read:find problems", "Gate:see the findings above"],
    Roadmap::Drop => [GATE, "Read:find the item", "Gate:no item %{item_id} on roadmap %{slug}", "Step:drop the item", "Read:say what was dropped"],
    Roadmap::Log => [GATE, "Step:write the log line", "Read:say what was logged"],
    Roadmap::Next => [GATE, "Read:find the first ready item, or say what is in the way"],
    Roadmap::Show => [GATE, "Read:print each batch and item"]
  }.freeze

  def test_each_of_the_five_roadmap_workflows_lists_its_steps_with_the_gate_first
    assert_equal STEPS, STEPS.keys.to_h { |flow| [flow, listed(flow)] }
  end

  def test_each_of_the_five_inherits_from_the_roadmap_workflow
    assert_equal [Roadmap::RoadmapWorkflow], STEPS.keys.map(&:superclass).uniq
  end

  def test_a_second_load_of_a_roadmap_workflow_keeps_the_gate_first_and_once
    path = File.expand_path("../../../../../lib/plastic/workflows/code/roadmap/show.rb", __dir__)

    assert SecondLoad.keeps?(path) { listed(Roadmap::Show) == STEPS.fetch(Roadmap::Show) }
  end

  def test_the_roadmap_gate_declares_the_gate_of_a_roadmap_that_does_not_exist
    flow = Class.new(Roadmap::RoadmapWorkflow) { roadmap_gate }

    assert_equal [GATE], listed(flow)
  end

  def test_a_subclass_of_a_roadmap_workflow_gets_no_gate_it_did_not_ask_for
    assert_empty Class.new(Roadmap::Check).steps
  end

  def test_the_roadmap_workflow_is_in_no_registry
    assert_empty Plastic::Workflows::REGISTRY.values.grep(/RoadmapWorkflow/)
  end

  private

  def listed(flow) = flow.steps.map { |step| "#{step.class.name.split("::").last}:#{step.respond_to?(:reason) ? step.reason : step.name}" }
end
