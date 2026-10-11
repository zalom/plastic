# frozen_string_literal: true

require_relative "cli/command/usage"
require_relative "harnesses/harness"

module Plastic
  # The harnesses Plastic ships support for, in the order detection tries
  # them. See docs/reference/harness-adapters.md.
  module Harnesses
    EVENTS = { "SessionStart" => "hook start", "Stop" => "hook stop", "SessionEnd" => "hook end" }.freeze

    REGISTRY = [
      Harness.new(name: "claude-code", session_variables: %w[CLAUDE_CODE_SESSION_ID], transcript: "/\\.claude/projects/",
        process: "claude", event_field: nil, events: EVENTS, settings: ".claude/settings.json", doctor: :ClaudeCode,
        installer: "claude"),
      Harness.new(name: "codex", session_variables: %w[CODEX_THREAD_ID CODEX_SESSION_ID], transcript: "/\\.codex/sessions/",
        process: "codex", event_field: :turn_id, events: EVENTS, settings: ".codex/hooks.json", doctor: :Codex,
        installer: "codex")
    ].freeze

    def self.all = REGISTRY

    def self.names = REGISTRY.map(&:name)

    def self.registered?(name) = names.include?(name)

    def self.installed_by(installer) = REGISTRY.find { |harness| harness.installer == installer }

    def self.found(home:, path:) = REGISTRY.select { |harness| harness.found?(home:, path:) }

    def self.found_in(scope) = found(home: scope.home, path: scope.setting("PATH", ""))

    def self.sessions(env) = REGISTRY.to_h { |harness| [harness.name, harness.session(env)] }.compact

    def self.nearest(processes, among: names)
      candidates = REGISTRY.select { |harness| among.include?(harness.name) }.to_h { |harness| [harness.process, harness] }
      candidates[processes.ancestors.find { |process| candidates.key?(process) }]
    end

    def self.fetch(name)
      REGISTRY.find { |harness| harness.name == name } or
        raise CLI::Command::Usage, "no harness #{name}; the registered harnesses are #{names.join(", ")}"
    end
  end
end
