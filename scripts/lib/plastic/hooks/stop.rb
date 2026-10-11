# frozen_string_literal: true

require "json"
require_relative "../hook"
require_relative "../config"
require_relative "../graph"
require_relative "../harnesses"
require_relative "stop_gate"

module Plastic
  module Hooks
    # Stop: stamps the session's last turn, renews its live locks, then runs
    # the stop gate.
    class Stop < Hook
      def respond(event)
        return no_session unless session_id

        stop(event)
      end

      private

      def no_session
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end

      def graphs = (@graphs ||= Graph.open(home: scope.plastic_home, store: scope.slug, session: session_id))

      def stop(event)
        work = graphs.work
        work.stamp_turn(session_id, directory:)
        work.renew_locks(session_id)
        decision = StopGate.new(event:, stop_hook: stop_hook?, retrieval: graphs.retrieval, session_id:).decision
        decision && JSON.generate(decision)
      end

      def stop_hook? = Config.new(scope.plastic_home, harness: harness).flag(%w[runner stop_hook], default: false)

      def harness = graphs.retrieval.session(session_id)&.harness.then { |name| name if Harnesses.registered?(name) }
    end
  end
end
