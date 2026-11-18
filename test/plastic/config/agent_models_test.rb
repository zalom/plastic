# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/config/agent_models"

class AgentModelsTest < Plastic::TestCase
  def test_a_value_that_is_not_a_tier_alias_has_no_effort_and_no_codex_model
    assert_equal [nil, nil], [Plastic::Config::AgentModels.effort_for("gpt-5.6-sol"), Plastic::Config::AgentModels.codex_model_for("gpt-5.6-sol")]
  end

  def test_the_codex_harness_maps_a_tier_to_its_codex_model
    assert_equal "gpt-5.6-terra", Plastic::Config::AgentModels.shipped_model_for("plastic-executor", harness: "codex")
  end

  def test_a_consultation_agent_takes_its_own_codex_model
    assert_equal "gpt-6-astra", Plastic::Config::AgentModels.shipped_model_for("plastic-secondary-advisor", harness: "codex")
  end

  def test_the_claude_harness_keeps_the_shipped_alias
    assert_equal "fable", Plastic::Config::AgentModels.shipped_model_for("plastic-primary-advisor")
  end

  def test_the_planner_tier_is_opus
    assert_equal "opus", Plastic::Config::AgentModels.shipped_model_for("plastic-planner")
  end

  def test_every_tier_names_a_shipped_agent_file
    agents = File.expand_path("../../../agents", __dir__)

    assert_empty(Plastic::Config::AgentModels::TIER_DEFAULTS.keys.reject { |name| File.exist?(File.join(agents, "#{name}.md")) })
  end

  def test_an_agent_with_no_shipped_effort_takes_the_default
    assert_equal ["high", "medium"], [Plastic::Config::AgentModels.shipped_effort_for("plastic-secondary-advisor"), Plastic::Config::AgentModels.shipped_effort_for("plastic-executor")]
  end
end
