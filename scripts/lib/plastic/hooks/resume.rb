# frozen_string_literal: true

require_relative "../hook"
require_relative "../graph"
require_relative "../doctor"
require_relative "recap"

module Plastic
  module Hooks
    # SessionStart: opens the session row, then prints the Recap the rows
    # alone carry, and one line naming plastic doctor when a doctor check
    # fails. Nothing here is call memory: a hook keeps no routine run.
    class Resume < Hook
      option :harness, switch: "--harness NAME", text: "the harness calling this hook", default: "claude-code"

      # The doctor run the hook asks: the failing checks of the whole doctor for this scope.
      FAILING_CHECKS = ->(scope) { Doctor.checks(scope, Doctor.kind(Doctor.harness(scope)), running: nil).select(&:repair) }

      def initialize(argv, health: FAILING_CHECKS, **rest)
        super(argv, **rest)
        @health = health
      end

      def respond(event)
        graphs = Graph.open(home: scope.plastic_home, store: scope.slug, session: session_id)
        open_session_row(graphs.work)
        recap = Recap.new(graphs.retrieval, session_id:, source: event[:source], directory:).lines
        [*recap, doctor_line].compact.join("\n")
      end

      private

      def doctor_line
        failing = @health.call(scope)
        "Plastic: doctor found #{failing.size} failing #{(failing.size == 1) ? "check" : "checks"}; run plastic doctor." unless failing.empty?
      rescue => error
        environment.err.puts "plastic hook: #{error.message}"
        nil
      end

      # The store's databases stay out of its versioning before any read.
      def open_session_row(work)
        work.ignore_databases
        return environment.err.puts("plastic hook: the event names no session; nothing recorded") unless session_id

        work.open_session(session_id, harness: parsed[:harness], directory:)
      end
    end
  end
end
