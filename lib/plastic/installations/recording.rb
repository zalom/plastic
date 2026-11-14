# frozen_string_literal: true

require "json"
require_relative "layout"
require_relative "record"
require_relative "roots"
require_relative "engine_permissions"
require_relative "agent_record"
require_relative "files"
require_relative "marked_section"
require_relative "package"

module Plastic
  module Installations
    # The record of one harness, read from what its install left on disk:
    # the manifest, the Plastic entries in its settings file and the marked
    # section of its instruction file.
    class Recording
def self.layouts
  claude = MarkedSection::CLAUDE
  codex = MarkedSection::CODEX
  {
    "claude" => Layout.new(:dir, "settings.json", :claude_purge_command?, "CLAUDE.md", [claude.begin_prefix, claude.end_marker]),
    "codex" => Layout.new(:home_dir, "hooks.json", :codex_purge_command?, "AGENTS.md", [codex.begin_prefix, codex.end_marker]),
    "hermes" => Layout.new(:dir, nil, nil, nil, [])
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
  manifest = AgentRecord.new(@config).manifest
  manifest.files + [manifest.path].select { |path| File.file?(path) }
end

      def settings_path = @layout.settings_path(@config)

      def settings = (@settings ||= settings_path ? Hash(Files.read_json(settings_path)) : {})

      def hooks = Hash(settings["hooks"]).flat_map { |event, groups| owned_entries(event, groups) }

      def owned_entries(event, groups)
        commands(groups).select { |command| owned?(command) }.map { |command| { "event" => event, "command" => command } }
      end

      def commands(groups) = Array(groups).grep(Hash).flat_map { |group| Array(group["hooks"]) }.grep(Hash).map { |hook| hook["command"] }

      def owned?(command) = @layout.plastic?(command) || package.entries.own?(command.to_s)

      def package = Package.new(@installer.package_root, @installer.plastic_home, @installer.version)

      def status_line
        line = settings["statusLine"]
        command = line["command"] if line.is_a?(Hash)
        { "command" => command, "replaced" => replaced } if command && @layout.plastic?(command)
      end

      def replaced
        original = Files.read_json(File.join(@installer.plastic_home, ".cache", "original-statusline.json"))
        original if original.is_a?(Hash)
      end

      def permissions
        rules = settings["permissions"]
        (EnginePermissions::ENTRIES + EnginePermissions::RETIRED) & Array(rules.is_a?(Hash) && rules["deny"])
      end

      def sections
        opening, closing = @layout.markers
        path = @layout.instructions_path(@config)&.then { |file| Files.resolve(file) }
        return [] unless path && File.file?(path) && File.read(path).include?(opening)

        [{ "file" => path, "begin" => opening, "end" => closing }]
      end
    end
  end
end
