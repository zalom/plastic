# frozen_string_literal: true

require_relative "../harnesses"
require_relative "files"
require_relative "hook_purge"
require_relative "report"

module Plastic
  module Installations
    # Merges Plastic's hooks into the hooks.json of Codex: the same shape as
    # the hooks of Claude Code's settings.json. Entries an earlier install
    # wrote through the retired dispatcher go first, then the kernel entries.
    class CodexHooks
      def initialize(package)
        @package = package
      end

      # Returns the hook words whose line changed, because Codex asks the
      # person to trust each changed line again.
      def merge(path)
        data = Files.read_json(path) || {}
        before = Report.pairs(Hash(data["hooks"]))
        Report.removed_hooks(HookPurge.new(:codex_purge_command?).call(data["hooks"] ||= {}), "hooks.json")
        data = @package.entries.codex(data)
        Files.write_json(path, data)
        changed(Report.pairs(data["hooks"]) - before)
      end

      private

      def changed(added)
        commands = added.map(&:last)
        Harnesses.fetch("codex").events.values.select { |words| commands.any? { |command| command.include?("\" #{words} ") } }
      end
    end
  end
end
