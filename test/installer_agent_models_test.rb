# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"

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
    g = { "agents" => { "models" => { "plastic-executor" => "haiku" } } }
    map = AgentModels.override_map(project_config: {}, global_config: g)
    assert_equal "haiku", map["plastic-executor"]
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

  # --- The two advisor agents (intent 185 final design): plastic-advisor
  # (real, ships fable) and plastic-faux-advisor (imitation, ships opus).
  # Each ships its own default in frontmatter, not a hard-wired exception ---

  def test_consultation_agents_contains_exactly_the_two_advisors
    assert_equal %w[plastic-advisor plastic-faux-advisor], AgentModels::CONSULTATION_AGENTS
  end

  def test_tier_defaults_excludes_every_consultation_agent
    AgentModels::CONSULTATION_AGENTS.each do |basename|
      refute AgentModels::TIER_DEFAULTS.key?(basename),
        "TIER_DEFAULTS must not contain #{basename}: consultation agents are not lifecycle-stage roles"
    end
  end

  def test_tier_defaults_and_consultation_agents_together_classify_every_shipped_agent
    # Deliberately matches install_agents' own agents/*.md glob (scripts/lib/installer_core.rb),
    # not doctor's narrower runtime plastic-* glob, so an unprefixed shipped agent cannot slip
    # past this guard.
    real_basenames = Dir[File.join(WORKTREE, "agents", "*.md")]
                        .map { |f| File.basename(f, ".md") }

    overlap = AgentModels::TIER_DEFAULTS.keys & AgentModels::CONSULTATION_AGENTS
    assert_empty overlap,
      "TIER_DEFAULTS and CONSULTATION_AGENTS must stay disjoint, found in both: #{overlap.inspect}"

    classified = AgentModels::TIER_DEFAULTS.keys + AgentModels::CONSULTATION_AGENTS
    unclassified = real_basenames - classified
    assert_empty unclassified,
      "every shipped agents/*.md basename must be a TIER_DEFAULTS key or a " \
      "CONSULTATION_AGENTS member (add it to scripts/lib/agent_models.rb): #{unclassified.inspect}"
  end

  def test_install_agents_preserves_each_advisors_shipped_default_model
    @core.install_agents(@dest)
    assert_equal "model: fable", model_line("plastic-advisor")
    assert_equal "model: opus", model_line("plastic-faux-advisor")
  end

  def test_install_agents_rewrites_advisor_model_on_override
    @core.install_agents(@dest, models: { "plastic-advisor" => "opus", "plastic-faux-advisor" => "fable" })
    assert_equal "model: opus", model_line("plastic-advisor")
    assert_equal "model: fable", model_line("plastic-faux-advisor")
  end

  def write_global_config(hash)
    File.write(File.join(@home, "config.yml"), YAML.dump(hash))
  end

  def write_project_config(project_dir, hash)
    FileUtils.mkdir_p(File.join(project_dir, ".plastic_store"))
    File.write(File.join(project_dir, ".plastic_store", "config.yml"), YAML.dump(hash))
  end

  # --- Harness-scoped agents.models (intent 185 final design): the legacy
  # flat form (agents.models.<name>: value) is honored as the claude harness
  # only; nested agents.models.<harness>.<name> wins over flat for the same
  # agent; a non-claude harness reads ONLY its own nested sub-hash, never the
  # flat entries or the claude sub-hash. This closes a real latent bug:
  # previously the same flat map fed both the Claude frontmatter rewrite and
  # the Codex TOML generator, so a literal Claude model id could leak into a
  # Codex config. ---

  def test_models_section_reads_flat_form_as_claude
    g = { "agents" => { "models" => { "plastic-executor" => "opus" } } }
    assert_equal({ "plastic-executor" => "opus" }, AgentModels.models_section(g, harness: "claude"))
  end

  def test_models_section_flat_form_never_applies_to_codex
    g = { "agents" => { "models" => { "plastic-executor" => "opus" } } }
    assert_equal({}, AgentModels.models_section(g, harness: "codex"))
  end

  def test_models_section_nested_wins_over_flat_for_claude
    g = { "agents" => { "models" => { "plastic-executor" => "opus", "claude" => { "plastic-executor" => "sonnet" } } } }
    assert_equal "sonnet", AgentModels.models_section(g, harness: "claude")["plastic-executor"]
  end

  def test_models_section_reads_codex_nested_sub_hash
    g = { "agents" => { "models" => { "codex" => { "plastic-executor" => "gpt-5.1-codex" } } } }
    assert_equal({ "plastic-executor" => "gpt-5.1-codex" }, AgentModels.models_section(g, harness: "codex"))
  end

  def test_override_map_defaults_to_claude_harness
    g = { "agents" => { "models" => { "plastic-executor" => "opus" } } }
    assert_equal({ "plastic-executor" => "opus" }, AgentModels.override_map(global_config: g))
  end

  # The literal-model-id-leak regression proof: a literal Claude model id set
  # under the flat legacy form must never reach
  # InstallerCore#agent_model_overrides(harness: "codex"), the map
  # install_codex feeds straight into generate_codex_agents.
  def test_agent_model_overrides_never_leaks_a_claude_model_id_into_codex
    write_global_config("agents" => { "models" => { "plastic-executor" => "claude-opus-4-8-literal-id" } })
    claude_map = @core.agent_model_overrides
    codex_map = @core.agent_model_overrides(harness: "codex")

    assert_equal "claude-opus-4-8-literal-id", claude_map["plastic-executor"]
    refute codex_map.key?("plastic-executor"),
      "a literal Claude model id under the flat/claude form must never leak into the codex-scoped override map"
  end

  def test_agent_model_overrides_reads_codex_scoped_entries_only_for_codex_harness
    write_global_config("agents" => { "models" => {
      "codex" => { "plastic-executor" => "gpt-5.1-codex" },
      "claude" => { "plastic-executor" => "sonnet" },
    } })
    codex_map = @core.agent_model_overrides(harness: "codex")
    claude_map = @core.agent_model_overrides

    assert_equal "gpt-5.1-codex", codex_map["plastic-executor"]
    assert_equal "sonnet", claude_map["plastic-executor"]
  end

  # --- advisor.enabled / apply_config_flags (intent 185 final design):
  # advisor.claude.default names an AGENT, never a model; --advisor accepts
  # the agent name or the "real"/"faux" shorthand ---

  def test_apply_config_flags_no_advisor_disables
    @core.apply_config_flags(["--no-advisor"])
    config = YAML.safe_load(File.read(File.join(@home, "config.yml")))
    assert_equal false, config.dig("advisor", "enabled")
  end

  def test_apply_config_flags_advisor_shorthand_real_writes_plastic_advisor
    @core.apply_config_flags(["--advisor", "real"])
    config = YAML.safe_load(File.read(File.join(@home, "config.yml")))
    assert_equal "plastic-advisor", config.dig("advisor", "claude", "default")
  end

  def test_apply_config_flags_advisor_shorthand_faux_writes_plastic_faux_advisor
    @core.apply_config_flags(["--advisor", "faux"])
    config = YAML.safe_load(File.read(File.join(@home, "config.yml")))
    assert_equal "plastic-faux-advisor", config.dig("advisor", "claude", "default")
  end

  def test_apply_config_flags_advisor_value_passes_through_a_literal_agent_name
    @core.apply_config_flags(["--advisor", "my-custom-advisor"])
    config = YAML.safe_load(File.read(File.join(@home, "config.yml")))
    assert_equal "my-custom-advisor", config.dig("advisor", "claude", "default")
  end

  def test_apply_config_flags_absent_flags_write_nothing
    @core.apply_config_flags([])
    refute File.exist?(File.join(@home, "config.yml")),
      "apply_config_flags must not create config.yml when no relevant flag is present"
  end
end
