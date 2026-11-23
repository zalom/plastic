# frozen_string_literal: true

require_relative "../cli/hook"
require_relative "../graph"
require_relative "../cli/wiring"

module Plastic
  module Hooks
    # SessionEnd: sets the session's end time and the reason the event names, then releases its node and driver claims.
    # With backup.daily on, it then takes the end-of-day backup of every store.
    class End < CLI::Hook
      changes(local: "The end time and the reason are written to the session row", work: "The node claims and the driver claims of the session are released", backups: "With backup.daily on, every store takes its end-of-day backup, which replaces the earlier one of the day")

      def respond(event)
        return no_session unless session_id

        work = Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: session_id, clock: environment.clock).work
        work.end_session(session_id, reason: event[:reason])
        work.release_claims(session_id)
        nil
      end

      private

      def back_up_the_day = CLI::DayBackup.new(environment).back_up(:end_session)

      def no_session
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end
    end
  end
end
