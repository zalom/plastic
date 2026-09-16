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
  # The three per-kind node agents (intent 340b, G7c, n2), dispatched by
  # HarnessAdapter::AGENT_TYPE_BY_KIND. work and research resolve the
  # executor tier, verify the advisor tier, mirroring RunnerPolicy's
  # model_role split (327 D12): work and research run on plastic-executor's
  # own tier, verify on the same tier plastic-advisor's imitation
  # (plastic-faux-advisor) ships, never the cheap tier.
  TIER_DEFAULTS = {
    "plastic-enforcer" => "opus",
    "plastic-executor" => "sonnet",
    "plastic-node-work" => "sonnet",
    "plastic-node-verify" => "opus",
    "plastic-node-research" => "sonnet"
  }.freeze

  # The two advisor agents (intent 185 final design): plastic-advisor (the real
  # advisor, ships `model: fable`) and plastic-faux-advisor (the imitation
  # advisor, an ordinary model carrying the same reasoning discipline inline,
  # ships `model: opus`). Both are shipped DEFAULTS in frontmatter, never a
  # hard-wired identity: agents.models.claude.<name> (or the legacy flat form)
  # overrides either one through the same install-time frontmatter rewrite
  # every agent override uses. Neither is a lifecycle-stage role: never
  # dispatched by the auto pipeline, not part of TIER_DEFAULTS. Codex installs
  # pair plastic-advisor with Sol and plastic-faux-advisor with Terra.
  CONSULTATION_AGENTS = %w[plastic-primary-advisor plastic-secondary-advisor].freeze

  SHIPPED_MODEL_DEFAULTS = TIER_DEFAULTS.merge(
    "plastic-primary-advisor" => "fable",
    "plastic-secondary-advisor" => "fable"
  ).freeze

  # Codex reasoning effort per tier alias. Model choice and reasoning effort are independent:
  # aliases select the recommended OpenAI model, while every Plastic role starts at medium.
  # A valid harness-scoped user override can still choose another effort for one agent.
  EFFORT_BY_ALIAS = {
    "opus" => "medium",
    "sonnet" => "medium",
    "haiku" => "medium"
  }.freeze

  DEFAULT_EFFORT = "medium"

  SHIPPED_EFFORT_DEFAULTS = {
    "plastic-primary-advisor" => "medium",
    "plastic-secondary-advisor" => "high"
  }.freeze

  # Codex model id per tier alias (intent 186). Codex has NO vendor alias layer: every model id
  # is a literal versioned string that rots (gpt-5.2 / gpt-5.3-codex already deprecated), which is
  # why 116 D1 / 102a Decision B refused to pin a raw id per role file. This resolves that by
  # centralizing every id in ONE map: Plastic owns the alias, so per-role identity costs a single
  # line to refresh on a Codex deprecation plus a Plastic release, and no per-role file carries a
  # raw id. opus (deepest reasoning tier) -> the flagship Sol; sonnet (execution tier) -> the
  # balanced Terra; haiku (lightest) -> the fast/cheap Luna. This is a shipped
  # DEFAULT, fully overridable via agents.models.codex.<name>. Model strength does not change
  # effort: all three aliases use medium unless agents.efforts.codex.<name> overrides it.
  CODEX_MODEL_BY_ALIAS = {
    "opus" => "gpt-5.6-sol",
    "sonnet" => "gpt-5.6-terra",
    "haiku" => "gpt-5.6-luna"
  }.freeze

  CODEX_MODEL_BY_AGENT = {
    "plastic-primary-advisor" => "gpt-6-astra",
    "plastic-secondary-advisor" => "gpt-6-astra"
  }.freeze

  module_function

  def shipped_effort_for(agent)
    SHIPPED_EFFORT_DEFAULTS.fetch(agent.to_s, DEFAULT_EFFORT)
  end

  # Pull { basename => model } out of a loaded config hash's `agents.models`
  # section, scoped to `harness` ("claude" or "codex"), tolerating a missing or
  # malformed shape. `agents.models` can mix two shapes: legacy FLAT scalar
  # entries (agents.models.plastic-executor: sonnet), honored as the claude
  # harness only, and harness-scoped sub-hashes (agents.models.claude.*,
  # agents.models.codex.*). Nested wins over flat for the same agent on the
  # claude harness; a non-claude harness reads ONLY its own nested sub-hash,
  # never the flat entries, so a literal model id written under the flat form
  # (or agents.models.claude.*) can never leak into another harness's config.
  def models_section(config, harness: "claude")
    return {} unless config.is_a?(Hash)
    agents = config["agents"]
    return {} unless agents.is_a?(Hash)
    section = agents["models"]
    return {} unless section.is_a?(Hash)

    nested = section[harness]
    nested = nested.is_a?(Hash) ? nested : {}
    return nested unless harness == "claude"

    flat = section.reject { |_key, value| value.is_a?(Hash) }
    flat.merge(nested)
  end

  # Override map for the installer: global overrides overlaid by project
  # overrides (project wins), scoped to `harness`. Defaults are intentionally
  # excluded. Unknown agent keys are carried through as-is; install_agents
  # simply never matches them to a copied file, so they are ignored without
  # raising.
  def override_map(project_config: {}, global_config: {}, harness: "claude")
    models_section(global_config, harness: harness).merge(models_section(project_config, harness: harness))
  end

  def effort_override_map(project_config: {}, global_config: {}, harness: "claude")
    efforts_section(global_config, harness).merge(efforts_section(project_config, harness))
  end

  def efforts_section(config, harness)
    agents = config.is_a?(Hash) ? config["agents"] : nil
    efforts = agents.is_a?(Hash) ? agents["efforts"] : nil
    section = efforts.is_a?(Hash) ? efforts[harness] : nil
    section.is_a?(Hash) ? section : {}
  end

  # The model_reasoning_effort for a Plastic tier alias, or nil for any value that is not
  # one of the three shipped aliases (the caller treats nil as a literal Codex model id).
  def effort_for(value)
    EFFORT_BY_ALIAS[value.to_s]
  end

  # The Codex model id for a Plastic tier alias, or nil for any value that is not one of the three
  # shipped aliases (the caller then treats the value as a literal Codex model id, or omits it).
  def codex_model_for(value)
    CODEX_MODEL_BY_ALIAS[value.to_s]
  end

  def shipped_model_for(agent, harness: "claude")
    value = SHIPPED_MODEL_DEFAULTS[agent.to_s]
    return value unless harness.to_s == "codex"

    CODEX_MODEL_BY_AGENT[agent.to_s] || codex_model_for(value) || value
  end
end
