# frozen_string_literal: true

require "json"

module Plastic
  module Workflows
    # Reads the hook commands in the agent settings and checks that every
    # Plastic hook runs the active release launcher.
    class InstallationHooks
      LAUNCHER = %r{"([^"]+/bin/plastic)" hook }
      REINSTALL = "run plastic install --reinstall to point the hooks at the active release"

      def self.strings(node)
        case node
        when Hash then strings(node.values)
        when Array then node.flat_map { |item| strings(item) }
        else [node.to_s]
        end
      end

      def self.valid?(file)
        JSON.parse(File.read(file))
        true
      rescue JSON::ParserError
        false
      end

      def initialize(home:, active: nil)
        @home = home
        @active = active
      end

      def check
        InstallationHealth::Check.new("hooks:", *verdict)
      rescue JSON::ParserError => error
        file = error.message
        InstallationHealth::Check.new("hooks:", "#{file} is not valid JSON", "fix #{file} by hand")
      end

      # The settings file that does not parse, which an install would overwrite.
      def unreadable = files.find { |file| !self.class.valid?(file) }

      private

      attr_reader :home, :active

      def verdict
        return ["none registered", nil] if launchers.empty?

        stray = launchers.uniq - [active]
        stray.empty? ? ["point at the active release", nil] : ["point at #{stray.join(", ")}", REINSTALL]
      end

      def launchers
        @launchers ||= files.flat_map { |file| self.class.strings(parse(file)) }.filter_map { |text| text[LAUNCHER, 1] }
      end

      def files = [File.join(home, ".claude", "settings.json"), File.join(home, ".codex", "hooks.json")].select { |file| File.file?(file) }

      def parse(file)
        JSON.parse(File.read(file))
      rescue JSON::ParserError
        raise JSON::ParserError, file
      end
    end
  end
end
