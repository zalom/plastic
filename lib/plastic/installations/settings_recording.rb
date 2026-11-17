# frozen_string_literal: true

require "json"
require_relative "engine_permissions"
require_relative "files"
require_relative "package"

module Plastic
  module Installations
    # What a harness's settings file holds of Plastic: its hook entries, its
    # status line and the deny rules it added.
    class SettingsRecording
      def initialize(installer, layout, path)
        @installer = installer
        @layout = layout
        @settings = path ? Hash(Files.read_json(path)) : {}
      end

      def hooks = Hash(@settings["hooks"]).flat_map { |event, groups| owned_entries(event, groups) }

      def status_line
        line = @settings["statusLine"]
        command = line["command"] if line.is_a?(Hash)
        { "command" => command, "replaced" => replaced } if command && @layout.plastic?(command)
      end

      def permissions
        rules = @settings["permissions"]
        (EnginePermissions::ENTRIES + EnginePermissions::RETIRED) & Array(rules.is_a?(Hash) && rules["deny"])
      end

      private

      def owned_entries(event, groups)
        commands(groups).select { |command| owned?(command) }.map { |command| { "event" => event, "command" => command } }
      end

      def commands(groups) = Array(groups).grep(Hash).flat_map { |group| Array(group["hooks"]) }.grep(Hash).map { |hook| hook["command"] }

      def owned?(command) = @layout.plastic?(command) || package.entries.own?(command.to_s)

      def package = Package.new(@installer.package_root, @installer.plastic_home, @installer.version, @installer.clock)

      def replaced
        original = Files.read_json(File.join(@installer.plastic_home, ".cache", "original-statusline.json"))
        original if original.is_a?(Hash)
      end
    end
  end
end
