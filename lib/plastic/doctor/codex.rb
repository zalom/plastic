# frozen_string_literal: true

require_relative "version_record"
require_relative "instruction_line"
require_relative "codex_hooks"
require_relative "codex_location"

module Plastic
  module Doctor
    class Codex
      REPAIR = VersionRecord::REINSTALL
      PLASTIC_LINE = /PLASTIC\.md/

      def self.trust = Check.new("hook trust:", "not verified; open Codex /hooks and review the current Plastic definitions", nil)

      def initialize(scope, running:)
        @scope = scope
        @running = running
      end

      def checks = [record, CodexLocation.new(scope).check, *CodexHooks.new(File.join(folder, "hooks.json"), home: scope.home).checks, instructions, Codex.trust]

      private

      attr_reader :scope, :running

      def folder = File.join(scope.home, ".codex")

      def record
        path = File.join(scope.home, ".agents", "plastic", "VERSION")
        VersionRecord.new(path, running).check("codex record:", install: "plastic init")
      end

      def instructions
        file = File.join(folder, "AGENTS.md")
        Check.new("Codex AGENTS.md:", "#{file} names PLASTIC.md", REPAIR).judged(InstructionLine.new(file, PLASTIC_LINE).problem)
      end
    end
  end
end
