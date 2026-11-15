# frozen_string_literal: true

require "json"
require_relative "layout"
require_relative "record"
require_relative "roots"
require_relative "agent_record"
require_relative "files"
require_relative "marked_section"
require_relative "settings_recording"

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
          folders: Roots.new(roots).plastic_folders(written), settings: settings_path, hooks: settings.hooks,
          status_line: settings.status_line, permissions: settings.permissions, sections:)
      end

      private

      def roots = @config.values_at(:dir, :home_dir).compact

      def files
        AgentRecord.new(@config).manifest.files_and_path
      end

      def settings_path = @layout.settings_path(@config)

      def settings = (@settings ||= SettingsRecording.new(@installer, @layout, settings_path))

      def sections
        opening, closing = @layout.markers
        path = @layout.instructions_path(@config)&.then { |file| Files.resolve(file) }
        return [] unless path && File.file?(path) && File.read(path).include?(opening)

        [{ "file" => path, "begin" => opening, "end" => closing }]
      end
    end
  end
end
