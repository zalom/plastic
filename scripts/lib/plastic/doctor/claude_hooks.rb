# frozen_string_literal: true

require "json"
require_relative "check"
require_relative "../hooks/entries"

module Plastic
  module Doctor
    class ClaudeHooks
      REPAIR = "plastic install --claude --reinstall"
      PLASTIC_FILE = /\Aplastic(?:-|\z)/

      def initialize(path, home:)
        @path = path
        @home = home
      end

      def checks
        return [Check.finding("hooks:", "#{path} is missing", REPAIR)] unless File.file?(path)

        hooks = read
        Hooks::Entries::EVENTS.keys.map { |event| event_check(event, files(hooks[event])) }
      rescue JSON::ParserError
        [Check.finding("hooks:", "#{path} is not valid JSON", "fix the JSON in #{path}, then run #{REPAIR}")]
      end

      private

      attr_reader :path, :home

      def read = Hash(Hash.try_convert(JSON.parse(File.read(path)))&.fetch("hooks", nil))

      def event_check(event, files)
        label = "hook #{event}:"
        return Check.finding(label, "no Plastic hook", REPAIR) if files.empty?

        broken = files.reject { |file| File.file?(file) && File.executable?(file) }
        Check.of(label, broken.empty? ? nil : "#{broken.join(", ")} is missing or not executable",
          detail: files.map { |file| File.basename(file) }.uniq.join(", "), repair: REPAIR)
      end

      def files(groups) = commands(groups).flat_map { |command| plastic_files(command) }

      def commands(groups) = Array(groups).flat_map { |group| Array(group["hooks"]) }.filter_map { |hook| hook["command"] }

      def plastic_files(command)
        command.split.map { |word| word.delete(%q("')).sub(%r{\A~/}, "#{home}/") }
          .select { |word| word.include?("/") && PLASTIC_FILE.match?(File.basename(word)) }
      end
    end
  end
end
