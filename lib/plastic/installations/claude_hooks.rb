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
      def initialize(package, claude_dir, registered: HookRegistry.events)
        @package = package
        @registered = registered
        @hook_dir = File.join(claude_dir, "hooks")
        @cache = File.join(package.home, ".cache")
      end

      def self.purge(hooks)
        hooks.delete("statusLine")
        removed = HookPurge.new(:claude_purge_command?).call(hooks)
        Report.reserved_hooks(hooks)
        removed
      end

      def merge(path)
        settings = merged(path)
        settings["statusLine"] = { "type" => "command", "command" => "#{@hook_dir}/plastic-statusline" } if @package.choices.statusline?
        Files.write_json(path, settings)
      end

      def merge_keeping_status_line(path) = Files.write_json(path, merged(path))

      private

      def merged(path)
        settings = Files.read_json(path) || {}
        removed = ClaudeHooks.purge(settings["hooks"] ||= {})
        settings = @package.entries.claude(settings)
        hooks = settings.fetch("hooks")
        add_registered(hooks)
        Report.removed_hooks(removed - Report.pairs(hooks), "settings.json")
        original = settings["statusLine"]
        keep_original(original) if original
        settings
      end

      def add_registered(hooks)
        HookRegistry.claude_settings_hooks(hook_dir: @hook_dir, registered: @registered).each do |event, group|
          (hooks[event] ||= []).concat([group].flatten)
        end
      end

      def keep_original(status)
        return if HookRegistry.claude_purge_command?(status["command"])

        FileUtils.mkdir_p(@cache)
        Files.write_json(File.join(@cache, "original-statusline.json"), status)
      end
    end
  end
end
