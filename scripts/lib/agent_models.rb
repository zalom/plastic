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

  # Consultation agent (intent 185, single-agent rename 185 ACTION-5) pins `fable`
  # in shipped frontmatter by design, plastic- prefixed like every other Plastic
  # agent. Not a lifecycle-stage role: never dispatched by the auto pipeline, not
  # part of TIER_DEFAULTS, Claude-only (generate_codex_agents skips authored-fable
  # agents; Codex has no fable alias). agents.models overrides still apply.
  CONSULTATION_AGENTS = %w[plastic-fable-advisor].freeze

  # Codex reasoning-effort per tier alias (intent 102a). model_reasoning_effort is a
  # depth-of-thinking dial independent of model selection (181 line 317-318), so mapping
  # the tier here never encodes a rotting Codex model id (116 D1). opus is the deepest
  # reasoning tier -> the deepest generally-safe effort (high, not the model-dependent
  # xhigh); sonnet the mid execution tier -> medium; haiku the lightest -> low. minimal is
  # unused.
  EFFORT_BY_ALIAS = {
    "opus" => "high",
    "sonnet" => "medium",
    "haiku" => "low"
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

  # The model_reasoning_effort for a Plastic tier alias, or nil for any value that is not
  # one of the three shipped aliases (the caller treats nil as a literal Codex model id).
  def effort_for(value)
    EFFORT_BY_ALIAS[value.to_s]
  end
end
