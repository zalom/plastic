# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/config/agent_models"

class AgentModelsTest < Plastic::TestCase
  def config(models)
    { "agents" => { "models" => models } }
  end

  def test_a_flat_entry_counts_for_the_claude_harness
    assert_equal({ "plastic-executor" => "haiku" }, Plastic::Config::AgentModels.models_section(config("plastic-executor" => "haiku")))
  end

  def test_a_nested_claude_entry_wins_over_a_flat_one
    models = config("plastic-executor" => "haiku", "claude" => { "plastic-executor" => "opus" })

    assert_equal({ "plastic-executor" => "opus" }, Plastic::Config::AgentModels.models_section(models))
  end

  def test_the_codex_harness_never_reads_a_flat_entry
    assert_empty Plastic::Config::AgentModels.models_section(config("plastic-executor" => "haiku"), harness: "codex")
  end

  def test_a_malformed_models_section_reads_as_empty
    assert_empty Plastic::Config::AgentModels.models_section(config("not a hash"))
  end

  def test_a_project_override_wins_over_a_global_one
    map = Plastic::Config::AgentModels.override_map(project_config: config("plastic-executor" => "opus"), global_config: config("plastic-executor" => "haiku"))

    assert_equal({ "plastic-executor" => "opus" }, map)
  end

  def test_effort_overrides_read_only_their_own_harness
    efforts = { "agents" => { "efforts" => { "codex" => { "plastic-executor" => "high" }, "claude" => { "plastic-executor" => "low" } } } }

    assert_equal({ "plastic-executor" => "high" }, Plastic::Config::AgentModels.effort_override_map(global_config: efforts, harness: "codex"))
  end

  def test_a_config_that_is_not_a_mapping_reads_as_empty
    models = Plastic::Config::AgentModels

    assert_equal [{}, {}, {}], [models.models_section("text"), models.models_section({ "agents" => "text" }), models.effort_override_map(project_config: "text")]
  end

  def test_a_malformed_efforts_section_reads_as_empty
    assert_empty Plastic::Config::AgentModels.effort_override_map(project_config: { "agents" => { "efforts" => [] } })
  end

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
