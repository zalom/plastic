# frozen_string_literal: true

require_relative "../graph/work/last_log_lines"
require_relative "../graph/work/session_intent"

module Plastic
  module Hooks
    # What a session start prints after a compaction: the session's intent, its claims, the
    # ready nodes, the last work log lines, the session note and the one next command. A session with no intent
    # gets one line.
    class CompactRecap
      FIRST_LINE = "Plastic: the session was compacted. The rows below carry the state; run plastic graph resume."
      NO_INTENT = "Plastic: the session was compacted and holds no intent. Run plastic next."
      LOG_LINES = 5

      def initialize(retrieval, session_id:)
        @retrieval = retrieval
        @session = Graph::Work::SessionIntent.new(retrieval, session_id)
        @session_id = session_id
      end

      def lines
        intent = @session.intent
        return [NO_INTENT] unless intent

        [FIRST_LINE, "intent: #{intent.label}", *claim_lines(intent), *ready_lines(intent), *log_lines(intent), *note_line, "next: #{next_command(intent)}"]
      end

      private

      def claims = @session.claims

      def note_line
        text = @retrieval.session(@session_id)&.note
        text ? ["note: #{text}"] : []
      end

      def claim_lines(intent) = claims.select { |node| node.intent_id == intent.intent_id }.map { |node| "claim: #{node.id} #{node.title}" }

      def ready(intent) = @retrieval.ready_nodes(intent.intent_id)

      def ready_lines(intent) = ready(intent).map { |node| "ready: #{node.id} #{node.title}" }

      def log_lines(intent) = Graph::Work::LastLogLines.new(@retrieval, LOG_LINES).lines(intent.intent_id)

      def next_command(intent)
        return "plastic graph resume" if claims.any? { |node| node.intent_id == intent.intent_id }

        node = ready(intent).first
        node ? "plastic node claim #{intent.intent_id} #{node.id}" : "plastic next"
      end
    end
  end
end
