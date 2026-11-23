# frozen_string_literal: true

require "json"
require_relative "../cli/hook"
require_relative "../cli/wiring"
require_relative "../graph"
require_relative "../harnesses"
require_relative "stop_gate"
require_relative "chat_record"
require_relative "chat_reply"

module Plastic
  module Hooks
    # Stop: stamps the session's last turn, renews its node claims, then runs
    # the stop gate.
    class Stop < CLI::Hook
      changes(local: "The last turn of the session is stamped, and the reply is added to the chat history when chat_sync is full", work: "The node claims and the driver claims of the session are renewed")

      def respond(event)
        return no_session unless session_id

        stop(event)
      end

      private

      def no_session
        environment.err.puts "plastic hook: the event names no session; nothing recorded"
        nil
      end

      def graphs = (@graphs ||= Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: session_id, clock: environment.clock))

      def stop(event)
        record_turn
        decision = StopGate.new(event:, stop_hook: stop_hook?, retrieval: graphs.retrieval, session_id:, now: environment.now).decision
        record_reply(event)
        decision && JSON.generate(decision)
      end

      def record_turn
        work = graphs.work
        work.stamp_turn(session_id, directory:)
        work.renew_claims(session_id)
      end

      def record_reply(event)
        chat_reply.call(event)
      rescue => error
        environment.err.puts "plastic hook: the reply was not recorded: #{Failed.describe(error)}"
      end

      def chat_reply
        home = scope.plastic_home
        record = ChatRecord.new(scope:, session_id:, environment:, graphs:)
        ChatReply.new(Wiring.config(home, harness:), record)
      end

      def stop_hook? = Wiring.config(scope.plastic_home, harness: harness).flag(%w[runner stop_hook], default: false)

      def harness = graphs.retrieval.session(session_id).harness.then { |name| name if Harnesses.registered?(name) }
    end
  end
end
