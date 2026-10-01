# frozen_string_literal: true

require "forwardable"
require_relative "../routine_run"
require_relative "session_reader"
require_relative "source"
require_relative "link"
require_relative "roadmap"

module Plastic
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes. A method that
    # takes an intent id reads every intent of the store when given none.
    class RetrievalGraph
      extend Forwardable

      attr_reader :store

      def_delegators :sessions, :routine_run, :session, :previous_session, :predecessor, :locks_of, :lock, :last_run, :touched

      def initialize(databases, store:, origin:)
        @databases = databases
        @store = store
        @origin = origin
      end

      def origin_id = @origin.id

      READY_NODES_SQL = <<~SQL
        SELECT * FROM nodes
        WHERE intent_id = :intent_id AND origin_id = :origin
          AND state = 'open'
          AND NOT EXISTS (
            SELECT 1 FROM edges JOIN nodes AS from_node
              ON from_node.intent_id = edges.intent_id AND from_node.id = edges."from"
            WHERE edges.intent_id = nodes.intent_id AND edges.kind = 'needs' AND edges."to" = nodes.id
              AND from_node.state IS NOT 'done'
          )
        ORDER BY id
      SQL

      # Nodes of `intent_id` ready to run: state nil, empty or pending, with
      # every `needs` edge into them satisfied (graph/edge.rb: `to` waits
      # until `from` is done).
      def ready_nodes(intent_id)
        @databases.fetch(:work).rows(READY_NODES_SQL, intent_id:, origin: origin_id).map { |row| Node.from_h(row) }
      end

      # This installation's intents, in Luhmann order.
      def intents = read(:intents).sort_by(&:segments)

      def intent(intent_id) = intents.find { |intent| intent.intent_id == intent_id }

      def clusters = read(:clusters)

      def documents(intent_id = nil) = read(:documents, intent_id)

      def savepoints(intent_id = nil) = read(:savepoints, intent_id)

      def nodes(intent_id = nil) = read(:nodes, intent_id)

      def node(intent_id, id) = nodes(intent_id).find { |node| node.id == id }

      def edges(intent_id = nil) = read(:edges, intent_id)

      def rulings(intent_id = nil) = read(:rulings, intent_id)

      LINKS_SQL = 'SELECT * FROM links WHERE origin_id = :origin AND (from_ref = :ref OR to_ref = :ref) ORDER BY "at"'

      # Links naming `ref` at either end: a ruling's ref today, any ref later.
      def links(ref) = @databases.fetch(:knowledge).rows(LINKS_SQL, origin: origin_id, ref:).map { |row| Link.from_h(row) }

      ROADMAP_SQL = "SELECT * FROM roadmaps WHERE origin_id = :origin AND slug = :slug"
      BATCHES_SQL = "SELECT * FROM batches WHERE origin_id = :origin AND roadmap = :slug ORDER BY position"
      ITEMS_SQL = "SELECT * FROM roadmap_items WHERE origin_id = :origin AND roadmap = :slug ORDER BY batch, position"
      ROADMAP_EDGES_SQL = "SELECT * FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :slug"
      ROADMAP_LOG_SQL = "SELECT * FROM roadmap_log WHERE origin_id = :origin AND roadmap = :slug ORDER BY position"

      # One roadmap by slug, or nil when none has been started.
      def roadmap(slug)
        row = @databases.fetch(:work).row(ROADMAP_SQL, origin: origin_id, slug:)
        row && Roadmap.from_h(row)
      end

      def batches(slug)
        @databases.fetch(:work).rows(BATCHES_SQL, origin: origin_id, slug:).map { |row| RoadmapBatch.from_h(row) }
      end

      def roadmap_items(slug)
        @databases.fetch(:work).rows(ITEMS_SQL, origin: origin_id, slug:).map { |row| RoadmapItem.from_h(row) }
      end

      def roadmap_edges(slug)
        @databases.fetch(:work).rows(ROADMAP_EDGES_SQL, origin: origin_id, slug:).map { |row| RoadmapEdge.from_h(row) }
      end

      def roadmap_log(slug)
        @databases.fetch(:work).rows(ROADMAP_LOG_SQL, origin: origin_id, slug:).map { |row| RoadmapLogLine.from_h(row) }
      end

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

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
