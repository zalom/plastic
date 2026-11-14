# frozen_string_literal: true

require "fileutils"
require_relative "files"
require_relative "hook_purge"
require_relative "hook_registry"
require_relative "report"

module Plastic
  module Installations
    # Merges Plastic's hooks and status line into the settings.json of Claude
    # Code. It reads, changes and writes the file, and never replaces what the
    # person put there: only entries the registry owns are rewritten.
    class ClaudeHooks
      def initialize(package, claude_dir)
        @package = package
        @hook_dir = File.join(claude_dir, "hooks")
      end

      def merge(path, choice: :plastic)
        settings = Files.read_json(path) || {}
        removed = purge(settings["hooks"] ||= {})
        settings = @package.entries.claude(settings)
        add_registered(settings["hooks"])
        Report.removed_hooks(removed - Report.pairs(settings["hooks"]), "settings.json")
        status_line(settings, choice)
        Files.write_json(path, settings)
      end

      private

      def purge(hooks)
        hooks.delete("statusLine")
        removed = HookPurge.new(:claude_purge_command?).call(hooks)
        Report.reserved_hooks(hooks)
        removed
      end

      def add_registered(hooks)
        HookRegistry.claude_settings_hooks(hook_dir: @hook_dir).each do |event, group|
          (group.is_a?(Array) ? group : [group]).each { |entry| place(hooks[event] ||= [], entry) }
        end
      end

      def place(groups, entry)
        existing = groups.find { |group| group.is_a?(Hash) && group["matcher"] == entry["matcher"] && owned?(group) }
        if existing
          existing["hooks"] = entry["hooks"]
        else
          groups << entry
        end
      end

      def owned?(group)
        group["hooks"].is_a?(Array) && group["hooks"].any? { |hook| HookRegistry.claude_purge_command?(hook["command"]) }
      end

      def status_line(settings, choice)
        keep_original(settings["statusLine"])
        return unless choice == :plastic && @package.choices.statusline?

        settings["statusLine"] = { "type" => "command", "command" => "#{@hook_dir}/plastic-statusline" }
      end

      def keep_original(status)
        return if status.nil? || HookRegistry.claude_purge_command?(status["command"])

        cache = File.join(@package.home, ".cache")
        FileUtils.mkdir_p(cache)
        Files.write_json(File.join(cache, "original-statusline.json"), status)
      end
    end
  end
end
