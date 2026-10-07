# frozen_string_literal: true

require_relative "cli/command/usage"
require_relative "doctor/core"
require_relative "doctor/claude_code"

module Plastic
  module Doctor
    HARNESSES = { "claude-code" => ClaudeCode }.freeze
    CODEX_VARIABLES = %w[CODEX_THREAD_ID CODEX_SESSION_ID].freeze

    def self.harness(scope, named) = named || (codex?(scope) ? "codex" : "claude-code")

    def self.codex?(scope) = CODEX_VARIABLES.any? { |name| !scope.setting(name).to_s.strip.empty? }

    def self.checks(scope, harness:, running:, harnesses: HARNESSES)
      kind = harnesses.fetch(harness) do
        raise CLI::Command::Usage, "no doctor for the harness #{harness}; harnesses with one: #{harnesses.keys.join(", ")}"
      end
      Core.new(scope, running:).checks + kind.new(scope, running:).checks
    end
  end
end
