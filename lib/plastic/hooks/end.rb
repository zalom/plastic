# frozen_string_literal: true

require_relative "../cli/hook"
require_relative "../graph"
require_relative "../cli/wiring"

module Plastic
  module Hooks
    # SessionEnd: sets the session's end time and the reason the event names.
    # With backup.daily on, it takes the end-of-day backup of every store first.
    class End < CLI::Hook
      changes(local: "The end time and the reason are written to the session row", backups: "With backup.daily on, every store takes its end-of-day backup, which replaces the earlier one of the day")

      def respond(event)
        return no_session unless session_id

        Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: session_id).work.end_session(session_id, reason: event[:reason])
        nil
      end

      private

      def back_up_the_day = CLI::DayBackup.new(environment).take(:end_session)

      def no_session
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end
    end
  end
end
