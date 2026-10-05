# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli/agent_options"

class AgentOptionsTest < Plastic::TestCase
  class Declared
    extend Plastic::CLI::Declarations
  end

  def declared = Class.new(Declared) { extend Plastic::CLI::AgentOptions }

  def test_extending_a_command_declares_the_agent_switches_and_the_dry_run
    assert_equal %w[--claude --codex --hermes --all --dry-run], declared.options.map(&:switch)
  end

  def test_every_agent_switch_is_off_by_default
    assert_equal [false], declared.options.map(&:default).uniq
  end
end
