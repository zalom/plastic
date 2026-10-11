# frozen_string_literal: true

require "json"
require_relative "layout"
require_relative "record"
require_relative "roots"
require_relative "../../engine_permissions"

module Plastic
  module Installations
    # The record of one harness, read from what its install left on disk:
    # the manifest, the Plastic entries in its settings file and the marked
    # section of its instruction file.
    class Recording
      def self.layouts
        core = ::InstallerCore
        {
          "claude" => Layout.new(:dir, "settings.json", :claude_purge_command?, "CLAUDE.md",
            [core::CLAUDE_SECTION_BEGIN_PREFIX, core::CLAUDE_SECTION_END]),
          "codex" => Layout.new(:home_dir, "hooks.json", :codex_purge_command?, "AGENTS.md",
            [core::CODEX_SECTION_BEGIN_PREFIX, core::CODEX_SECTION_END])
        }
      end

      def initialize(installer, harness)
        key = harness.installer
        @installer = installer
        @harness = harness
        @config = installer.agent_config(key)
        @layout = self.class.layouts.fetch(key)
      end

      def call
        written = files
        Record.new(harness: @harness.name, version: @installer.version, roots:, files: written,
          folders: Roots.new(roots).plastic_folders(written), settings: settings_path, hooks:, status_line:,
          permissions:, sections:)
      end

      private

      def roots = @config.values_at(:dir, :home_dir).compact

      def files
        manifest = @installer.manifest_path_for(@config[:key], @config)
        @installer.manifest_files(manifest) + [manifest].select { |path| File.file?(path) }
      end

      def settings_path = @layout.settings_path(@config)

      def settings = (@settings ||= Hash(@installer.read_json_safe(settings_path)))

      def hooks = Hash(settings["hooks"]).flat_map { |event, groups| owned_entries(event, groups) }

      def owned_entries(event, groups)
        commands(groups).select { |command| owned?(command) }.map { |command| { "event" => event, "command" => command } }
      end

      def commands(groups) = Array(groups).grep(Hash).flat_map { |group| Array(group["hooks"]) }.grep(Hash).map { |hook| hook["command"] }

      def owned?(command) = @installer.uninstalled_hook?(@layout.method(:plastic?), command)

      def status_line
        line = settings["statusLine"]
        command = line["command"] if line.is_a?(Hash)
        { "command" => command, "replaced" => replaced } if command && @layout.plastic?(command)
      end

      def replaced
        original = @installer.read_json_safe(File.join(@installer.plastic_home, ".cache", "original-statusline.json"))
        original if original.is_a?(Hash)
      end

      def permissions
        rules = settings["permissions"]
        EnginePermissions::ENTRIES & Array(rules.is_a?(Hash) && rules["deny"])
      end

      def sections
        opening, closing = @layout.markers
        path = @installer.resolve_managed_path(@layout.instructions_path(@config))
        return [] unless File.file?(path) && File.read(path).include?(opening)

        [{ "file" => path, "begin" => opening, "end" => closing }]
      end
    end
  end
end
