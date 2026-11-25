# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/second_load"

class RegistryTest < Plastic::TestCase
  def test_every_offer_names_a_command_in_this_build
    offers = Plastic::Workflows::REGISTRY.keys.flat_map { |key| Plastic::Workflow.fetch(key, from: Plastic::Workflows).outcomes.filter_map(&:offers) }.reject { |offer| offer.start_with?("%{") }
    missing = offers.reject { |command| Plastic::CLI.find(command.delete_prefix("plastic ").split) }

    assert_empty missing, "a next: line names a command not in Plastic::CLI::TABLE"
  end

  def test_a_second_load_of_each_workflow_file_that_clears_its_declarations_keeps_them
    keys = Plastic::Workflows::REGISTRY.keys.select { |key| File.read(workflow_path(key)).include?("clear_declarations") }
    changed = keys.reject do |key|
      flow = Plastic::Workflow.fetch(key, from: Plastic::Workflows)
      before = declarations(flow)
      SecondLoad.keeps?(workflow_path(key)) { declarations(flow) == before }
    end

    assert_operator keys.size, :>, 60, "the workflow files that clear their declarations"
    assert_empty changed, "a second load changed the declarations of these workflows"
  end

  private

  def workflow_path(key) = File.expand_path("../../../lib/plastic/workflows/#{Plastic::Workflow::Key.parse(key, Plastic::Workflows::REGISTRY.fetch(key)).file}.rb", __dir__)

  def declarations(flow)
    [flow.facts.dup, flow.steps.map { |step| plain(step) }, flow.outcomes.map { |outcome| plain(outcome) }]
  end

  def plain(declared) = declared.to_h.reject { |_name, value| value.respond_to?(:call) }
end
