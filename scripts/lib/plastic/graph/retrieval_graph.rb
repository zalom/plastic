# frozen_string_literal: true

require "forwardable"
require_relative "../routine_run"
require_relative "session_reader"
require_relative "work_reader"
require_relative "source"

module Plastic
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes. A method that
    # takes an intent id reads every intent of the store when given none.
    class RetrievalGraph
      extend Forwardable

      attr_reader :store

      def_delegators :sessions, :routine_run, :session, :previous_session, :predecessor, :locks_of, :lock, :last_run, :touched
      def_delegators :work, :ready_nodes, :node, :rulings, :links

      def initialize(databases, store:, origin:)
        @databases = databases
        @store = store
        @origin = origin
      end

      def origin_id = @origin.id

      # This installation's intents, in Luhmann order.
      def intents = read(:intents).sort_by(&:segments)

      def intent(intent_id) = intents.find { |intent| intent.intent_id == intent_id }

      def clusters = read(:clusters)

      def documents(intent_id = nil) = read(:documents, intent_id)

      def savepoints(intent_id = nil) = read(:savepoints, intent_id)

      def nodes(intent_id = nil) = read(:nodes, intent_id)

      def edges(intent_id = nil) = read(:edges, intent_id)

      # Kept files with no bytes: a print compares the hash and reads the bytes only to write.
      def kept_files(intent_id = nil) = read(:kept_files, intent_id)

      def kept_file_data(name)
        row = @databases.fetch(:references).row("SELECT hex(data) AS data FROM sqlar WHERE name = :name", name:)
        [row.fetch("data")].pack("H*")
      end

      # The hash of every file printed from the store's rows, by path.
      def printed
        Schema::STORE.flat_map { |key| @databases.fetch(key).rows("SELECT path, sha256 FROM printed") }
          .to_h { |row| row.values_at("path", "sha256") }
      end

      private

      def sessions = (@sessions ||= SessionReader.new(@databases, store:, origin: @origin))

      def work = (@work ||= WorkReader.new(@databases, origin: @origin))

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
