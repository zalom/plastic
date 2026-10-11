# frozen_string_literal: true

require "json"
require_relative "check"
require_relative "codex_hook_command"

module Plastic
  module Doctor
    class CodexHooks
      REPAIR = "plastic install --codex --reinstall"

      def self.commands(groups)
        Array(groups).grep(Hash).flat_map { |group| Array(group["hooks"]).grep(Hash) }
          .select { |hook| hook["type"] == "command" }.filter_map { |hook| hook["command"] }
      end

      def self.read(path)
        data = JSON.parse(File.read(path))
        data["hooks"] if data.is_a?(Hash)
      end

      def self.finding(problem) = Check.finding("hooks:", problem, REPAIR)

      def self.event_check(event, files)
        label = "hook #{event}:"
        return Check.finding(label, "no current Plastic hook for Codex", REPAIR) if files.empty?

        Check.new(label, files.uniq.join(", "), REPAIR).judged(Check.unrunnable(files))
      end

      def initialize(path, home:)
        @path = path
        @home = home
      end

      def checks
        return [CodexHooks.finding("#{path} is missing")] unless File.file?(path)

        checks_for(CodexHooks.read(path))
      rescue JSON::ParserError
        [Check.invalid_json(path, REPAIR)]
      end

      private

      attr_reader :path, :home

      def checks_for(hooks)
        return [CodexHooks.finding("#{path} must hold a hooks map")] unless hooks.is_a?(Hash)

        Harnesses.fetch("codex").events.keys.map { |event| CodexHooks.event_check(event, files(event, hooks[event])) }
      end

      def files(event, groups)
        CodexHooks.commands(groups).filter_map { |command| CodexHookCommand.new(command, home:).launcher(event) }
      end
    end
  end
end
