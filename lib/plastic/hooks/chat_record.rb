# frozen_string_literal: true

require_relative "../cli/wiring"
require_relative "../graph"
require_relative "../graph/work/chat/writer"
require_relative "../graph/work/session_intent"

module Plastic
  module Hooks
    # Writes one message of a session to the chat history of the machine. The history sits in plastic.db, so a
    # message is kept when no store resolves; its store and intent are then empty.
    class ChatRecord
      def initialize(home:, slug:, session_id:, clock:)
        @home = home
        @slug = slug
        @session_id = session_id
        @clock = clock
      end

      def call(role:, text:)
        graphs = open_graphs
        writer(graphs).record(session_id: @session_id, harness: harness(graphs), intent_id: intent_id(graphs), role:, text:)
      end

      private

      def open_graphs
        Wiring.graphs(home: @home, store: @slug, session: @session_id, clock: @clock)
      rescue Graph::MissingStore
        nil
      end

      def writer(graphs) = Graph::Work::Chat::Writer.new(Graph::Database.open_local(@home).fetch(:local), store: graphs&.retrieval&.store, clock: @clock)

      def harness(graphs) = graphs&.retrieval&.session(@session_id)&.harness

      def intent_id(graphs) = graphs && Graph::Work::SessionIntent.new(graphs.retrieval, @session_id).intent&.intent_id
    end
  end
end
