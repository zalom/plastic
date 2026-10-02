# frozen_string_literal: true

require_relative "../../test_helper"

class RegistryTest < Plastic::TestCase
  def test_every_offer_names_a_command_in_this_build
    offers = Plastic::Workflows::REGISTRY.flat_map { |key| Plastic::Workflow.fetch(key).outcomes.filter_map(&:offers) }
    missing = offers.reject { |command| Plastic::CLI.find(command.delete_prefix("plastic ").split) }

    assert_empty missing, "a next: line names a command not in Plastic::CLI::TABLE"
  end
end
