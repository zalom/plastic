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

      FAILING_CHECKS = ->(scope, harness) { Doctor.failing(scope, harness:) }

      DOCTOR_LINE = lambda do |count|
        "Plastic: doctor found #{count} failing #{(count == 1) ? "check" : "checks"}; run plastic doctor."
      end

      def initialize(argv, health: FAILING_CHECKS, **rest)
        super(argv, **rest)
        @health = health
      end

      def respond(event)
        [*recap(event), doctor_line].compact.join("\n")
      end

      private

      def recap(event)
        graphs = Graph.open(home: scope.plastic_home, store: scope.slug, session: session_id)
        open_session_row(graphs.work)
        Recap.new(graphs.retrieval, session_id:, source: event[:source], directory:).lines
      end

      def doctor_line = failing_count.then { |count| DOCTOR_LINE.call(count) if count.positive? }

      def failing_count
        @health.call(scope, parsed[:harness]).size
      rescue => error
        environment.err.puts "plastic hook: #{error.message}"
        0
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
