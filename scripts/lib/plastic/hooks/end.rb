# frozen_string_literal: true

require_relative "../hook"
require_relative "../graph"

module Plastic
  module Hooks
    # SessionEnd: sets the session's end time and the reason the event names.
    class End < Hook
      def respond(event)
        return no_session unless session_id

        Graph.open(home: scope.plastic_home, store: scope.slug, session: session_id).work.end_session(session_id, reason: event[:reason])
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
