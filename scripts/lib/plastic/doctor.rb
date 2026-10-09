# frozen_string_literal: true

require_relative "cli/command/usage"
require_relative "doctor/core"
require_relative "doctor/claude_code"
require_relative "doctor/codex"
require_relative "workflows/installation"

module Plastic
  module Doctor
    HARNESSES = { "claude-code" => ClaudeCode, "codex" => Codex }.freeze
    CODEX_VARIABLES = %w[CODEX_THREAD_ID CODEX_SESSION_ID].freeze

    def self.harness(scope) = codex?(scope) ? "codex" : "claude-code"

    def self.codex?(scope) = CODEX_VARIABLES.any? { |name| !scope.setting(name).to_s.strip.empty? }

    def self.kind(name, harnesses = HARNESSES)
      harnesses.fetch(name) do
        raise CLI::Command::Usage, "no doctor for the harness #{name}; harnesses with one: #{harnesses.keys.join(", ")}"
      end
    end

    def self.checks(scope, kind, running:) = Core.new(scope, running:).checks + kind.new(scope, running:).checks

    def self.run(scope, harness:)
      checks(scope, kind(harness), running: Workflows::Installation.running(scope))
    end

    def self.failing(scope, harness:) = run(scope, harness:).select(&:repair)
  end
end
