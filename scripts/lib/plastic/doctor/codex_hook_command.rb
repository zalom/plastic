# frozen_string_literal: true

require "shellwords"
require_relative "../hooks/entries"

module Plastic
  module Doctor
    class CodexHookCommand
      def self.words(command)
        tokens = Shellwords.split(command.to_s)
        tokens = tokens.drop(3) if tokens.first(3) == %w[env -u RUBYOPT]
        tokens = tokens.take(tokens.size - 2) if tokens.last(2) == %w[|| true]
        tokens
      rescue ArgumentError
        []
      end

      def self.plastic?(path) = path.include?("/") && File.basename(path) == "plastic"

      def initialize(command, home:)
        @command = command
        @home = home
      end

      def launcher(event)
        tokens = CodexHookCommand.words(command)
        path = tokens.first.to_s
        expected = Hooks::Entries::EVENTS.fetch(event).then { |words| format(words, "codex") }.split
        expand(path) if CodexHookCommand.plastic?(path) && tokens.drop(1) == expected
      end

      private

      attr_reader :command, :home

      def expand(path) = path.sub(%r{\A~/}, "#{home}/")
    end
  end
end
