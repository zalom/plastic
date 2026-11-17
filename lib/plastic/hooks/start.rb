# frozen_string_literal: true

require_relative "../hook"
require_relative "../graph"
require_relative "../wiring"
require_relative "../doctor"
require_relative "../workflows/installation"
require_relative "../graph/backup/due"
require_relative "../harnesses/detection"
require_relative "recap"
require_relative "doctor_line"

module Plastic
  module Hooks
    # SessionStart: names the harness, opens the session row with it, then
    # prints the Recap the rows alone carry, and, on a session that starts
    # fresh, one line naming plastic doctor when a doctor check fails or when
    # the harness it recorded is not registered.
    # Nothing here is call memory: a hook keeps no command run.
    class Start < Hook
      changes(store: "The databases of the store are kept out of its versioning", local: "The session row of the call is opened or kept", backups: "The current and the global store take a backup when the newest is older than twelve hours")

      def initialize(argv, health: method(:failing_checks), **rest)
        super(argv, **rest)
        @health = health
      end

      def respond(event)
        back_up_stores
        doctor = DoctorLine.new(scope, harness, session_id:, health: @health, err: environment.err)
        [*recap(event), doctor.line(event[:source])].compact.join("\n")
      end

      private

      def failing_checks(scope, harness) = Doctor.failing(scope, harness:, running: Workflows::Installation.running(scope), now: environment.now)

      def back_up_stores
        [scope.slug, Scope::GLOBAL].uniq.each do |slug|
          Graph::Backup::Due.new(home: scope.plastic_home, slug:, now: environment.now).call("session start")
        end
      end

      def harness
        @harness ||= Harnesses::Detection.new(event:, env: environment.env, processes: environment.processes, session_id:).harness
      end

      def recap(event)
        graphs = Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: session_id, clock: environment.clock)
        open_session_row(graphs.work)
        recap_of(graphs.retrieval, event[:source]).lines(now: environment.now)
      end

      def recap_of(retrieval, source) = Recap.new(retrieval, session_id:, source:, directory:)

      # The store's databases stay out of its versioning before any read.
      def open_session_row(work)
        work.ignore_databases
        return environment.err.puts("plastic hook: the event names no session; nothing recorded") unless session_id

        work.open_session(session_id, harness:, directory:)
      end
    end
  end
end
