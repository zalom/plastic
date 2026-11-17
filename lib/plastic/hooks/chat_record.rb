# frozen_string_literal: true

require_relative "../cli/wiring"
require_relative "../errors"
require_relative "../graph"
require_relative "../graph/work/chat/writer"
require_relative "../graph/work/session_intent"

module Plastic
  module Hooks
    # Writes one message of a session to the chat history of the machine. The history sits in plastic.db, so a
    # message is kept when no store resolves or the store cannot be read; its store and intent are then empty.
    # The caller passes the graphs it already holds, or the record opens them.
    class ChatRecord
      Context = Data.define(:store, :harness, :intent_id)
      EMPTY = Context.new(nil, nil, nil)

      def initialize(scope:, session_id:, environment:, graphs: nil)
        @scope = scope
        @session_id = session_id
        @environment = environment
        @graphs = graphs
      end

      def call(role:, text:)
        found = context
        writer(found.store).record(session_id: @session_id, harness: found.harness, intent_id: found.intent_id, role:, text:)
      end

      private

      def context
        graphs = @graphs || open_graphs
        graphs ? read(graphs) : EMPTY
      rescue Graph::OutOfStep, SQLite3::Exception, Error => error
        @environment.err.puts "plastic hook: the store could not be read (#{Failed.describe(error)}); the message is recorded with no store and no intent"
        EMPTY
      end

      def open_graphs
        Wiring.graphs(home: @scope.plastic_home, store: @scope.slug, session: @session_id, clock: @environment.clock)
      rescue Graph::MissingStore
        nil
      end

      def read(graphs)
        retrieval = graphs.retrieval
        Context.new(retrieval.store, retrieval.session(@session_id)&.harness, Graph::Work::SessionIntent.new(retrieval, @session_id).intent&.intent_id)
      end

      def writer(store) = Graph::Work::Chat::Writer.new(Graph::Database.open_local(@scope.plastic_home).fetch(:local), store:, clock: @environment.clock)
    end
  end
end
