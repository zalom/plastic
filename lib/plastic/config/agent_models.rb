# frozen_string_literal: true

module Plastic
  class Config
    # Shared model-tier resolution for Plastic subagents.
    #
    # TIER_DEFAULTS mirrors the shipped `agents/*.md` frontmatter, so
    # `shipped_model_for` answers `agents.models.<basename>` with the built-in
    # default. The installer does NOT use TIER_DEFAULTS: it applies only genuine
    # config overrides, so shipped frontmatter with no override
    # passes through unchanged.
    module AgentModels
      # Claude Code aliases only (never pinned ids, never Fable). Keys are the agent
      # file basenames without the `.md` extension.
      TIER_DEFAULTS = {
        "plastic-planner" => "opus",
        "plastic-executor" => "sonnet",
        "plastic-driver" => "sonnet",
        "plastic-retriever" => "sonnet"
      }.freeze

      # An agent file that no longer ships, and the agent that took its place.
      RENAMED = { "plastic-enforcer" => "plastic-planner" }.freeze

      # The two consultation agents are Primary Advisor and Secondary Advisor.
      # Both ship Fable; Primary uses medium effort and Secondary uses high effort.
      # Both are shipped defaults in frontmatter, never a
      # hard-wired identity: agents.models.claude.<name> (or the legacy flat form)
      # overrides either one through the same install-time frontmatter rewrite
      # every agent override uses. Neither is a lifecycle-stage role: never
      # dispatched by the auto pipeline, not part of TIER_DEFAULTS. Codex installs
      # generate both advisors with Astra and preserve each role's effort.
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

      # Codex model id per tier alias. Codex has NO vendor alias layer: every model id
      # is a literal versioned string that rots (gpt-5.2 / gpt-5.3-codex already deprecated), which is
      # why no role file pins a raw id. Every id sits in ONE map instead: Plastic owns the alias,
      # so per-role identity costs a single
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
  end
end
