# frozen_string_literal: true

require_relative "../hook"
require_relative "../graph"
require_relative "../doctor"
require_relative "../harnesses/detection"
require_relative "recap"
require_relative "doctor_line"

module Plastic
  module Hooks
    # SessionStart: names the harness, opens the session row with it, then
    # prints the Recap the rows alone carry, and, on a session that starts
    # fresh, one line naming plastic doctor when a doctor check fails or when
    # the harness it recorded is not registered.
    # Nothing here is call memory: a hook keeps no routine run.
    class Start < Hook
      FAILING_CHECKS = ->(scope, harness) { Doctor.failing(scope, harness:) }

      def initialize(argv, health: FAILING_CHECKS, **rest)
        super(argv, **rest)
        @health = health
      end

      def respond(event)
        doctor = DoctorLine.new(scope, harness, session_id:, health: @health, err: environment.err)
        [*recap(event), doctor.line(event[:source])].compact.join("\n")
      end

      private

      def harness
        @harness ||= Harnesses::Detection.new(event:, env: environment.env, processes: environment.processes, session_id:).harness
      end

      def recap(event)
        graphs = Graph.open(home: scope.plastic_home, store: scope.slug, session: session_id)
        open_session_row(graphs.work)
        Recap.new(graphs.retrieval, session_id:, source: event[:source], directory:).lines
      end

      # The store's databases stay out of its versioning before any read.
      def open_session_row(work)
        work.ignore_databases
        return environment.err.puts("plastic hook: the event names no session; nothing recorded") unless session_id

        work.open_session(session_id, harness:, directory:)
      end
    end
  end
end
