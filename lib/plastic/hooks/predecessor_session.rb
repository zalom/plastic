# frozen_string_literal: true

module Plastic
  module Hooks
    # The session a recap reads back: after a clear, the one that ended in the
    # same directory; otherwise the store's latest other session.
    class PredecessorSession
      def initialize(retrieval, session_id:, source:, directory:)
        @retrieval = retrieval
        @session_id = session_id
        @source = source
        @directory = directory
      end

      # The session, or nil when the store holds no other one.
      def session = (@session ||= clear_session || @retrieval.previous_session(@session_id))

      # The lines that name the session and the files it touched.
      def lines
        return [] unless session

        ["previous #{session.summary}", *touched_line]
      end

      private

      def clear_session
        @source == "clear" && @retrieval.predecessor(@session_id, directory: @directory, prefer_reason: "clear")
      end

      def touched_line
        touched = @retrieval.touched(session.session_id).join(", ")
        touched.empty? ? [] : ["touched: #{touched}"]
      end
    end
  end
end
