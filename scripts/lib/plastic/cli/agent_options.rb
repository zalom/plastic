# frozen_string_literal: true

module Plastic
  class CLI
    # The agent switches the install and uninstall commands share. With no
    # switch, the call works on Claude Code.
    module AgentOptions
      def self.extended(command)
        command.option :claude, switch: "--claude", default: false, text: "Claude Code, the default"
        command.option :codex, switch: "--codex", default: false, text: "Codex CLI"
        command.option :hermes, switch: "--hermes", default: false, text: "Hermes"
        command.option :all, switch: "--all", default: false, text: "every agent"
        command.option :dry_run, switch: "--dry-run", default: false, text: "list what would change and change nothing"
      end
    end
  end
end
