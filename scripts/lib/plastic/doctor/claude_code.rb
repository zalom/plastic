# frozen_string_literal: true

require_relative "check"
require_relative "version_record"
require_relative "instruction_line"
require_relative "claude_hooks"
require_relative "../../compact_instructions"

module Plastic
  module Doctor
    class ClaudeCode
      IMPORT = CompactInstructions::BODY.lines.map(&:strip).find { |line| line.start_with?("@") }
      AGENTS_IMPORT = "@AGENTS.md"

      def initialize(scope, running:)
        @scope = scope
        @running = running
      end

      def checks = [record, *ClaudeHooks.new(File.join(folder, "settings.json"), home: scope.home).checks, import, *projects]

      private

      attr_reader :scope, :running

      def folder = File.join(scope.home, ".claude")

      def record = VersionRecord.new(File.join(folder, "plastic", "VERSION"), running).check("claude record:", install: "plastic install --claude")

      def import
        file = File.join(folder, "CLAUDE.md")
        Check.of("CLAUDE.md:", InstructionLine.new(file, line(IMPORT)).problem, detail: "#{file} imports PLASTIC.md", repair: ClaudeHooks::REPAIR)
      end

      def projects = scope.projects.map { |slug, path| project(slug, File.join(path, "CLAUDE.md")) }

      def project(slug, file)
        Check.of("CLAUDE.md #{slug}:", InstructionLine.new(file, line(AGENTS_IMPORT)).problem, detail: "#{file} imports AGENTS.md",
          repair: "add the line #{AGENTS_IMPORT} to #{file}")
      end

      def line(text) = /\A#{Regexp.escape(text)}\s*\z/
    end
  end
end
