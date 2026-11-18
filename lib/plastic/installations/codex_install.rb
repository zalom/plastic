# frozen_string_literal: true

require_relative "agent_install"
require_relative "codex_agents"
require_relative "codex_hooks"
require_relative "codex_instructions"
require_relative "marked_section"

module Plastic
  module Installations
    # The install for Codex: skills in the shared agents folder, one TOML file
    # for each role in the Codex home, the Plastic block in its AGENTS.md and
    # the hooks in its hooks.json.
    class CodexInstall < AgentInstall
      private

      def copy
        choices = package.choices
        skills(exclude: advisor_exclusions) +
          CodexAgents.new(package.root, models: choices.models(harness: "codex"), efforts: choices.efforts(harness: "codex"), skip: choices.skipped_roles)
            .call(File.join(home, "agents"))
      end

      def integrate
        FileUtils.mkdir_p(home)
        MarkedSection.new(MarkedSection::CODEX, CodexInstructions::BODY).inject(File.join(home, "AGENTS.md"))
        { changed_hooks: CodexHooks.new(package).merge(File.join(home, "hooks.json")) }
      end

      def home = record.config[:home_dir]
    end
  end
end
