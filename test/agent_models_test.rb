# frozen_string_literal: true

require_relative "test_helper"
require "agent_models"

class AgentModelsTest < Plastic::TestCase
  def config(models)
    { "agents" => { "models" => models } }
  end

  def test_a_flat_entry_counts_for_the_claude_harness
    assert_equal({ "plastic-executor" => "haiku" }, AgentModels.models_section(config("plastic-executor" => "haiku")))
  end

  def test_a_nested_claude_entry_wins_over_a_flat_one
    models = config("plastic-executor" => "haiku", "claude" => { "plastic-executor" => "opus" })

    assert_equal({ "plastic-executor" => "opus" }, AgentModels.models_section(models))
  end

  def test_the_codex_harness_never_reads_a_flat_entry
    assert_empty AgentModels.models_section(config("plastic-executor" => "haiku"), harness: "codex")
  end

  def test_a_malformed_models_section_reads_as_empty
    assert_empty AgentModels.models_section(config("not a hash"))
  end

  def test_a_project_override_wins_over_a_global_one
    map = AgentModels.override_map(project_config: config("plastic-executor" => "opus"), global_config: config("plastic-executor" => "haiku"))

    assert_equal({ "plastic-executor" => "opus" }, map)
  end

  def test_effort_overrides_read_only_their_own_harness
    efforts = { "agents" => { "efforts" => { "codex" => { "plastic-executor" => "high" }, "claude" => { "plastic-executor" => "low" } } } }

    assert_equal({ "plastic-executor" => "high" }, AgentModels.effort_override_map(global_config: efforts, harness: "codex"))
  end

  def test_a_malformed_efforts_section_reads_as_empty
    assert_empty AgentModels.effort_override_map(project_config: { "agents" => { "efforts" => [] } })
  end

  def test_a_value_that_is_not_a_tier_alias_has_no_effort_and_no_codex_model
    assert_equal [nil, nil], [AgentModels.effort_for("gpt-5.6-sol"), AgentModels.codex_model_for("gpt-5.6-sol")]
  end

  def test_the_codex_harness_maps_a_tier_to_its_codex_model
    assert_equal "gpt-5.6-terra", AgentModels.shipped_model_for("plastic-executor", harness: "codex")
  end

  def test_a_consultation_agent_takes_its_own_codex_model
    assert_equal "gpt-6-astra", AgentModels.shipped_model_for("plastic-secondary-advisor", harness: "codex")
  end

  def test_the_claude_harness_keeps_the_shipped_alias
    assert_equal "fable", AgentModels.shipped_model_for("plastic-primary-advisor")
  end

  def test_an_agent_with_no_shipped_effort_takes_the_default
    assert_equal ["high", "medium"], [AgentModels.shipped_effort_for("plastic-secondary-advisor"), AgentModels.shipped_effort_for("plastic-executor")]
  end
end
