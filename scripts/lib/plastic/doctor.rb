# frozen_string_literal: true

require_relative "cli/command/usage"
require_relative "doctor/core"
require_relative "doctor/claude_code"
require_relative "doctor/codex"
require_relative "workflows/installation"
require_relative "harnesses/detection"
require_relative "harnesses/session_rows"

module Plastic
  module Doctor
    HARNESSES = Harnesses.all.select(&:doctor).to_h { |harness| [harness.name, const_get(harness.doctor)] }.freeze

    # The harness on the session's row, else the one whose session variable
    # names the session. Nothing naming one is a usage error that names the
    # session's row when it records a harness the registry lacks.
    def self.harness(scope, session:)
      row = recorded(scope, session)
      [row, detected(scope, session)].find { |name| Harnesses.registered?(name) } or
        raise CLI::Command::Usage, "#{row ? unregistered(session, row) : "no harness names this call"}; " \
                                   "name one with --harness: #{HARNESSES.keys.join(", ")}"
    end

    def self.unregistered(session, harness)
      return "the session #{session} is recorded as #{harness}, a harness Plastic has no doctor for" unless harness == Harnesses::Detection::UNKNOWN

      "the session #{session} is recorded as unknown: its start hook found no sign of a registered harness"
    end

    def self.recorded(scope, session) = session && Harnesses::SessionRows.new(scope.plastic_home).harness(session)

    def self.detected(scope, session)
      Harnesses::Detection.new(event: {}, env: scope.method(:setting), processes: Harnesses::Processes.none, session_id: session).harness
    end

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
