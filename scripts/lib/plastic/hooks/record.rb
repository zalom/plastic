# frozen_string_literal: true

require "json"
require_relative "../hook"
require_relative "../config"
require_relative "stop_gate"

module Plastic
  module Hooks
    # Stop: stamps the session's last turn, renews its live locks, then runs
    # the stop gate. SessionEnd, with --end, only sets the end time and the
    # reason: no stamp, no renewal, no gate.
    class Record < Hook
      option :harness, switch: "--harness NAME", text: "the harness calling this hook", default: "claude-code"
      option :end, switch: "--end", text: "the session end event: set the reason and stop", default: false

      def respond(event)
        sid = session_id(event)
        return stderr_line if sid.nil?

        graphs = Graph.open(home: scope.plastic_home, store: scope.slug, session: sid)
        parsed[:end] ? end_session(graphs, sid, event) : stop(graphs, sid, event)
      end

      private

      def stderr_line
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end

      def end_session(graphs, sid, event)
        graphs.work.end_session(sid, reason: event[:reason])
        nil
      end

      def stop(graphs, sid, event)
        graphs.work.stamp_turn(sid, harness: parsed[:harness], directory: directory)
        graphs.work.renew_locks(sid)
        decision = StopGate.new(event:, stop_hook: stop_hook?, retrieval: graphs.retrieval, session_id: sid).decision
        decision && JSON.generate(decision)
      end

      def stop_hook? = Config.new(scope.plastic_home).flag(%w[runner stop_hook], default: false)
    end
  end
end
