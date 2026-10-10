# frozen_string_literal: true

require_relative "../../agent_models"

module Plastic
  class Config
    # The settings Plastic ships: one global set, and a set per harness that
    # holds the agent models and efforts and the default advisor.
    module Defaults
      GLOBAL = {
        "statusline" => true,
        "screens" => true,
        "runner" => { "stop_hook" => false },
        "review" => { "pull_request" => "required" },
        "migrate" => { "remove_after_import" => false },
        "advisor" => { "enabled" => true }
      }.freeze

      ADVISOR = "plastic-primary-advisor"
      MODEL_FAMILIES = { "codex" => "codex" }.freeze
      AGENTS = AgentModels::SHIPPED_MODEL_DEFAULTS.keys.freeze

      def self.harness(name) = { "agents" => agents(MODEL_FAMILIES.fetch(name, "claude")), "advisor" => { "default" => ADVISOR } }

      def self.agents(family)
        {
          "models" => per_agent { |agent| AgentModels.shipped_model_for(agent, harness: family) },
          "efforts" => per_agent { |agent| AgentModels.shipped_effort_for(agent) }
        }
      end

      def self.per_agent = AGENTS.to_h { |agent| [agent, yield(agent)] }
    end
  end
end
