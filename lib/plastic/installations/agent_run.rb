# frozen_string_literal: true

require_relative "claude_install"
require_relative "codex_install"
require_relative "hermes_install"
require_relative "skill_copy"
require_relative "transaction"

module Plastic
  module Installations
    # One agent's install inside its transaction, with the result keyed by
    # the agent.
    class AgentRun
      INSTALLS = { "claude" => ClaudeInstall, "codex" => CodexInstall, "hermes" => HermesInstall }.freeze

      def initialize(agents, package, statusline)
        @agents = agents
        @package = package
        @statusline = statusline
      end

      def call(key)
        record = @agents.record(key)
        return { agent: key, success: false, reason: "Unknown agent", key: key } unless record

        Transaction.new(@package.home, record, roots_of(record)).call { install_for(key, record).call }.merge(key: key)
      end

      private

      def roots_of(record) = record.roots(SkillCopy.new(@package.root, @package.home).fragments)

      def install_for(key, record)
        kind = INSTALLS.fetch(key)
        (key == "claude") ? kind.new(@package, record, statusline: @statusline) : kind.new(@package, record)
      end
    end
  end
end
