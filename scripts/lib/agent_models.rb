# frozen_string_literal: true

# Shared model-tier resolution for Plastic subagents (intent 116).
#
# TIER_DEFAULTS mirrors the shipped `agents/*.md` frontmatter so `read-config`
# can answer `agents.models.<basename>` with the built-in default. The installer
# does NOT use TIER_DEFAULTS: it applies only genuine config overrides via
# `override_map`, so shipped frontmatter with no override passes through
# unchanged.
module AgentModels
  # Claude Code aliases only (never pinned ids, never Fable). Keys are the agent
  # file basenames without the `.md` extension.
  TIER_DEFAULTS = {
    "plastic-enforcer" => "opus",
    "plastic-brainstorming" => "opus",
    "plastic-planner" => "opus",
    "plastic-spec-specialist" => "sonnet",
    "plastic-executor" => "sonnet",
    "plastic-intent-curator" => "sonnet",
    "plastic-future-intent-researcher" => "sonnet",
    "plastic-intent-discovery" => "sonnet"
  }.freeze

  module_function

  # Pull the `agents.models` sub-hash out of a loaded config hash, tolerating a
  # missing or malformed shape. Returns a plain { basename => model } hash.
  def models_section(config)
    return {} unless config.is_a?(Hash)
    agents = config["agents"]
    return {} unless agents.is_a?(Hash)
    section = agents["models"]
    section.is_a?(Hash) ? section : {}
  end

  # Override map for the installer: global overrides overlaid by project
  # overrides (project wins). Defaults are intentionally excluded. Unknown agent
  # keys are carried through as-is; install_agents simply never matches them to a
  # copied file, so they are ignored without raising.
  def override_map(project_config: {}, global_config: {})
    models_section(global_config).merge(models_section(project_config))
  end
end
