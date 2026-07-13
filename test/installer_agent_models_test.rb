# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/agent_models"
require_relative "../scripts/lib/installer_core"

# Per-agent model resolution + installer frontmatter rewrite (intent 116).
class InstallerAgentModelsTest < Minitest::Test
  WORKTREE = File.expand_path("../../", __FILE__)

  def setup
    @home = Dir.mktmpdir("agent-models")
    @core = InstallerCore.new(package_root: WORKTREE, plastic_home: @home, version: "0.0.0")
    @dest = File.join(@home, "agents")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def model_line(basename)
    File.read(File.join(@dest, "#{basename}.md"))[/^model:.*$/]
  end

  # --- pure resolver ---

  def test_project_override_wins_over_global
    g = { "agents" => { "models" => { "plastic-executor" => "opus" } } }
    p = { "agents" => { "models" => { "plastic-executor" => "sonnet" } } }
    map = AgentModels.override_map(project_config: p, global_config: g)
    assert_equal "sonnet", map["plastic-executor"]
  end

  def test_global_override_applies_absent_project
    g = { "agents" => { "models" => { "plastic-planner" => "haiku" } } }
    map = AgentModels.override_map(project_config: {}, global_config: g)
    assert_equal "haiku", map["plastic-planner"]
  end

  def test_unknown_agent_key_is_ignored_without_raising
    g = { "agents" => { "models" => { "plastic-does-not-exist" => "opus" } } }
    map = AgentModels.override_map(global_config: g)
    # resolver does not raise; installer never matches it to a copied file
    @core.install_agents(@dest, models: map)
    refute File.exist?(File.join(@dest, "plastic-does-not-exist.md"))
    assert_equal "model: sonnet", model_line("plastic-executor")
  end

  # --- installer rewrite ---

  def test_no_override_passthrough_preserves_shipped_default
    @core.install_agents(@dest)
    assert_equal "model: sonnet", model_line("plastic-executor")
    assert_equal "model: opus", model_line("plastic-enforcer")
  end

  def test_override_rewrites_model_line
    @core.install_agents(@dest, models: { "plastic-executor" => "opus" })
    assert_equal "model: opus", model_line("plastic-executor")
    # unlisted agent still passes through
    assert_equal "model: opus", model_line("plastic-enforcer")
  end

  # --- effort_for (intent 102a): Codex model_reasoning_effort mapping ---

  def test_effort_for_maps_the_three_shipped_aliases
    assert_equal "high", AgentModels.effort_for("opus")
    assert_equal "medium", AgentModels.effort_for("sonnet")
    assert_equal "low", AgentModels.effort_for("haiku")
  end

  def test_effort_for_returns_nil_for_a_non_alias_value
    assert_nil AgentModels.effort_for("gpt-5.4-codex")
    assert_nil AgentModels.effort_for("")
    assert_nil AgentModels.effort_for(nil)
  end

  # --- Consultation agent (intent 185, single-agent rename 185 ACTION-5): shipped fable exception ---

  def test_consultation_agents_contains_exactly_the_single_advisor
    assert_equal %w[plastic-fable-advisor], AgentModels::CONSULTATION_AGENTS
  end

  def test_tier_defaults_excludes_every_consultation_agent
    AgentModels::CONSULTATION_AGENTS.each do |basename|
      refute AgentModels::TIER_DEFAULTS.key?(basename),
        "TIER_DEFAULTS must not contain #{basename}: consultation agents are not lifecycle-stage roles"
    end
  end

  def test_install_agents_preserves_shipped_fable_model_for_advisor
    @core.install_agents(@dest)
    AgentModels::CONSULTATION_AGENTS.each do |basename|
      assert_equal "model: fable", model_line(basename)
    end
  end

  def test_install_agents_rewrites_fable_advisor_model_on_override
    @core.install_agents(@dest, models: { "plastic-fable-advisor" => "opus" })
    assert_equal "model: opus", model_line("plastic-fable-advisor")
  end
end
