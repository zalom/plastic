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
      IMPORT_LINE = /\A#{Regexp.escape(IMPORT)}\s*\z/
      AGENTS_IMPORT = "@AGENTS.md"
      AGENTS_LINE = /\A#{Regexp.escape(AGENTS_IMPORT)}\s*\z/

      def self.project(slug, file)
        Check.new("CLAUDE.md #{slug}:", "#{file} imports AGENTS.md", "add the line #{AGENTS_IMPORT} to #{file}")
          .judged(InstructionLine.new(file, AGENTS_LINE).problem)
      end

      def initialize(scope, running:)
        @scope = scope
        @running = running
      end

      def checks = [record, *ClaudeHooks.new(File.join(folder, "settings.json"), home: scope.home).checks, import, *projects]

      private

      attr_reader :scope, :running

      def folder = File.join(scope.home, ".claude")

      def record = VersionRecord.new(File.join(folder, "plastic", "VERSION"), running).check("claude record:", install: "plastic init")

      def import
        file = File.join(folder, "CLAUDE.md")
        Check.new("CLAUDE.md:", "#{file} imports PLASTIC.md", ClaudeHooks::REPAIR).judged(InstructionLine.new(file, IMPORT_LINE).problem)
      end

      def projects = scope.projects.map { |slug, path| ClaudeCode.project(slug, File.join(path, "CLAUDE.md")) }
    end
  end
end
