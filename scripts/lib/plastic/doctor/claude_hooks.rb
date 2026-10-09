# frozen_string_literal: true

require "json"
require_relative "check"
require_relative "codex_hook_command"
require_relative "../hooks/entries"

module Plastic
  module Doctor
    class ClaudeHooks
      REPAIR = "plastic install --claude --reinstall"
      PLASTIC_FILE = /\Aplastic(?:-|\z)/
      RETIRED = "hook record --end"

      def self.event_check(event, files)
        label = "hook #{event}:"
        return Check.finding(label, "no Plastic hook", REPAIR) if files.empty?

        Check.new(label, files.map { |file| File.basename(file) }.uniq.join(", "), REPAIR).judged(broken(files))
      end

      def self.broken(files)
        missing = files.reject { |file| File.file?(file) && File.executable?(file) }
        "#{missing.join(", ")} is missing or not executable" unless missing.empty?
      end

      def self.plastic_file?(path) = path.include?("/") && PLASTIC_FILE.match?(File.basename(path))

      def initialize(path, home:)
        @path = path
        @home = home
      end

      def checks
        return [Check.finding("hooks:", "#{path} is missing", REPAIR)] unless File.file?(path)

        hooks = read
        Hooks::Entries::EVENTS.keys.map { |event| event_check(event, hooks[event]) }
      rescue JSON::ParserError
        [Check.finding("hooks:", "#{path} is not valid JSON", "fix the JSON in #{path}, then run #{REPAIR}")]
      end

      private

      attr_reader :path, :home

      def event_check(event, groups)
        return Check.finding("hook #{event}:", "names the retired #{RETIRED}", REPAIR) if commands(groups).any? { |command| command.include?(RETIRED) }

        stale = stale_line(event, groups)
        return Check.finding("hook #{event}:", "names the stale command line #{stale}", REPAIR) if stale

        ClaudeHooks.event_check(event, files(groups))
      end

      def stale_line(event, groups)
        expected = Hooks::Entries::EVENTS.fetch(event).then { |words| format(words, "claude-code") }.split
        commands(groups).filter_map { |command| CodexHookCommand.new(command, home:).arguments }.find { |arguments| arguments != expected }&.join(" ")
      end

      def read = Hash(Hash.try_convert(JSON.parse(File.read(path)))&.fetch("hooks", nil))

      def files(groups) = commands(groups).flat_map { |command| plastic_files(command) }

      def commands(groups) = Array(groups).flat_map { |group| Array(group["hooks"]) }.filter_map { |hook| hook["command"] }

      def plastic_files(command) = command.split.map { |word| expand(word) }.select { |path| ClaudeHooks.plastic_file?(path) }

      def expand(word) = word.delete(%q("')).sub(%r{\A~/}, "#{home}/")
    end
  end
end
