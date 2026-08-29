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
    "plastic-executor" => "sonnet"
  }.freeze

  # The two advisor agents (intent 185 final design): plastic-advisor (the real
  # advisor, ships `model: fable`) and plastic-faux-advisor (the imitation
  # advisor, an ordinary model carrying the same reasoning discipline inline,
  # ships `model: opus`). Both are shipped DEFAULTS in frontmatter, never a
  # hard-wired identity: agents.models.claude.<name> (or the legacy flat form)
  # overrides either one through the same install-time frontmatter rewrite
  # every agent override uses. Neither is a lifecycle-stage role: never
  # dispatched by the auto pipeline, not part of TIER_DEFAULTS. Claude-only for
  # this release (generate_codex_agents skips both by name; the Codex advisor
  # case is intent 186, not a permanent exclusion).
  #
  # Intent 186 DEFINES the advisor Codex pairing but keeps emission deferred: when the skip is
  # lifted, plastic-advisor pairs to gpt-5.6-sol at xhigh (the deepest) and plastic-faux-advisor
  # to gpt-5.6-terra at high (cheaper). Neither is in TIER_DEFAULTS and neither is auto-dispatched.
  CONSULTATION_AGENTS = %w[plastic-advisor plastic-faux-advisor].freeze

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

  # Codex model id per tier alias (intent 186). Codex has NO vendor alias layer: every model id
  # is a literal versioned string that rots (gpt-5.2 / gpt-5.3-codex already deprecated), which is
  # why 116 D1 / 102a Decision B refused to pin a raw id per role file. This resolves that by
  # centralizing every id in ONE map: Plastic owns the alias, so per-role identity costs a single
  # line to refresh on a Codex deprecation plus a Plastic release, and no per-role file carries a
  # raw id. opus (deepest reasoning tier) -> the flagship Sol; sonnet (execution tier) -> the
  # balanced Terra; haiku (lightest) -> the fast/cheap Luna. Paired with EFFORT_BY_ALIAS so
  # reasoning roles get a stronger model AND higher effort than executors. This is a shipped
  # DEFAULT, fully overridable via agents.models.codex.<name>.
  CODEX_MODEL_BY_ALIAS = {
    "opus" => "gpt-5.6-sol",
    "sonnet" => "gpt-5.6-terra",
    "haiku" => "gpt-5.6-luna"
  }.freeze

  module_function

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
end
