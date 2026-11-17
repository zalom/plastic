# frozen_string_literal: true

require_relative "../cli/hook"
require_relative "../graph"
require_relative "../cli/wiring"

module Plastic
  module Hooks
    # SessionEnd: sets the session's end time and the reason the event names.
    class End < CLI::Hook
      changes(local: "The end time and the reason are written to the session row")

      def respond(event)
        return no_session unless session_id

        Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: session_id).work.end_session(session_id, reason: event[:reason])
        nil
      end

      private

      def no_session
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end
    end
  end
end
