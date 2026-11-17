# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/choices"

class ChoicesTest < Plastic::TestCase
  include PackageFixture
  def settings = (@settings ||= FakeSettings.new)

  def config_with(values) = @settings = FakeSettings.new(values:)

  def choices = Plastic::Installations::Choices.new(settings)

  def test_the_agent_models_come_from_the_config_of_the_harness
    config_with({ "agents.models.plastic-executor" => "gpt-x" })

    assert_equal({ "plastic-executor" => "gpt-x" }, choices.models(harness: "codex"))
    assert_equal ["codex"], settings.harnesses
  end

  def test_the_claude_models_come_from_the_config_of_claude_code
    choices.models

    assert_equal ["claude-code"], settings.harnesses
  end

  def test_the_agent_efforts_come_from_the_section_of_the_harness
    config_with({ "agents.efforts.plastic-executor" => "high" })

    assert_equal({ "plastic-executor" => "high" }, choices.efforts)
  end

  def test_the_advisor_is_on_by_default_and_off_when_the_global_section_turns_it_off
    assert_predicate choices, :advisor?
    config_with({ "advisor.enabled" => false })

    refute_predicate choices, :advisor?
  end

  def test_the_skipped_roles_are_the_advisors_only_when_the_advisor_is_off
    assert_empty choices.skipped_roles
    config_with({ "advisor.enabled" => false })

    assert_equal Plastic::Config::AgentModels::CONSULTATION_AGENTS, choices.skipped_roles
  end

  def test_the_status_line_is_off_by_default_and_on_when_the_flag_says_so
    refute_predicate choices, :statusline?
    config_with({ "statusline" => true })

    assert_predicate choices, :statusline?
  end
end
