# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/choices"

class ChoicesTest < Plastic::TestCase
  include PackageFixture
  include ConfigHomes

  def config_with(text) = seed_config(@plastic_home, text)

  def choices = Plastic::Installations::Choices.new(@plastic_home)

  def test_the_agent_models_come_from_the_section_of_the_harness
    config_with("global: {}\nharnesses:\n  codex:\n    agents:\n      models:\n        plastic-executor: gpt-x\n")

    assert_equal [{ "plastic-executor" => "gpt-x" }, {}], [choices.models(harness: "codex"), choices.models]
  end

  def test_the_agent_efforts_come_from_the_section_of_the_harness
    config_with("harnesses:\n  claude-code:\n    agents:\n      efforts:\n        plastic-executor: high\n")

    assert_equal({ "plastic-executor" => "high" }, choices.efforts)
  end

  def test_the_advisor_is_on_by_default_and_off_when_the_global_section_turns_it_off
    assert_predicate choices, :advisor?
    config_with("global:\n  advisor:\n    enabled: false\n")

    refute_predicate choices, :advisor?
  end

  def test_the_skipped_roles_are_the_advisors_only_when_the_advisor_is_off
    assert_empty choices.skipped_roles
    config_with("global:\n  advisor:\n    enabled: false\n")

    assert_equal Plastic::Config::AgentModels::CONSULTATION_AGENTS, choices.skipped_roles
  end

  def test_the_status_line_is_off_by_default_and_on_when_the_flag_says_so
    refute_predicate choices, :statusline?
    config_with("global:\n  statusline: true\n")

    assert_predicate choices, :statusline?
  end
end
