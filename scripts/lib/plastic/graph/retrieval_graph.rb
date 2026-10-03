# frozen_string_literal: true

require "forwardable"
require_relative "../routine_run"
require_relative "session_reader"
require_relative "work_reader"
require_relative "source"
require_relative "link"
require_relative "roadmap"
require_relative "archive"
require_relative "backup"
require_relative "evidence_writer"
require_relative "evidence_integrity"
require_relative "reference_backfill"
require_relative "retrieval_reference"
require_relative "retrieval_search"
require_relative "retrieval_store_read"

module Plastic
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes. A method that
    # takes an intent id reads every intent of the store when given none.
    class RetrievalGraph
      class MaintenanceRequired < StandardError; end
      class MissingReference < StandardError; end
      class InvalidSearch < StandardError; end
      SEARCH_LIMIT = RetrievalSearch::SEARCH_LIMIT
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
      def intents = read(:intents).sort_by(&:segments)

      def intent(intent_id)
        row = @databases.fetch(:work).row("SELECT * FROM intents WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id)
        row && Intent.from_h(row)
      end

      def unarchived_intents = intents.reject { |intent| archived?(intent.intent_id) }

      def completion(intent_id)
        @databases.fetch(:work).row("SELECT * FROM completions WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id)
      end

      def clusters = read(:clusters)

      def documents(intent_id = nil) = ensure_backfill! && read(:documents, intent_id)

      def fetch(intent_id, path) = ensure_backfill! && @databases.fetch(:knowledge).row(DOCUMENT_SQL, intent_id:, path:, origin: origin_id).then { |row| row && Document.from_h(row) }

      def reference(intent_id, path) = references.reference(intent_id, path)

      def fetch_reference(reference) = references.fetch(reference)

      def fetch_batch(references) = references.map { |reference| fetch_reference(reference) }

      def fetch_passage(reference, position) = references.fetch_passage(reference, position)

      def exact_lookup_plans(intent_id, path)
        [@databases.fetch(:work).rows("EXPLAIN QUERY PLAN SELECT * FROM intents WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id),
          @databases.fetch(:knowledge).rows("EXPLAIN QUERY PLAN #{DOCUMENT_SQL}", intent_id:, path:, origin: origin_id)]
      end

      DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"
      SEARCH_SQL = RetrievalSearch::SEARCH_SQL

      # Returns current indexed passages in stable lexical-rank order. Plain
      # words become quoted FTS terms, so caller text never changes the query.
      def search(terms, limit: 20, migrate: true)
        ensure_backfill!(migrate)
        searcher.call(terms, limit:)
      end

      def search_reference(row)
        references.qualified_reference(row.fetch("intent_id"), row.fetch("path"), row.fetch("sha256"))
      end

      def backfill!
        ReferenceBackfill.new(@databases, origin_id).call
      end

      def repair!
        EvidenceIntegrity.new(@databases.fetch(:knowledge), origin_id).repair!
      end

      def savepoints(intent_id = nil) = read(:savepoints, intent_id)

      def nodes(intent_id = nil) = read(:nodes, intent_id)

      def edges(intent_id = nil) = read(:edges, intent_id)

      LINKING_SQL = "SELECT * FROM links WHERE origin_id = :origin AND (to_ref = :id OR to_ref LIKE :prefix)"

      # Links whose to_ref is `id` or a ruling of it, such as "ID/D1".
      def linking(id)
        @databases.fetch(:knowledge).rows(LINKING_SQL, origin: origin_id, id:, prefix: "#{id}/%").map { |row| Link.from_h(row) }
      end

      ARCHIVE_SQL = "SELECT * FROM archives WHERE origin_id = :origin AND intent_id = :intent_id"

      # The intent's archive row, or nil when it was never archived.
      def archive_of(intent_id)
        row = @databases.fetch(:work).row(ARCHIVE_SQL, origin: origin_id, intent_id:)
        row && Archive.from_h(row)
      end

      # True while the intent has an archive row with no restored_at.
      def archived?(intent_id)
        archive = archive_of(intent_id)
        !archive.nil? && archive.restored_at.nil?
      end
      ROADMAP_SQL = "SELECT * FROM roadmaps WHERE origin_id = :origin AND slug = :slug"
      BATCHES_SQL = "SELECT * FROM batches WHERE origin_id = :origin AND roadmap = :slug ORDER BY position"
      ITEMS_SQL = "SELECT * FROM roadmap_items WHERE origin_id = :origin AND roadmap = :slug ORDER BY batch, position"
      ROADMAP_EDGES_SQL = 'SELECT * FROM roadmap_edges WHERE origin_id = :origin AND roadmap = :slug ORDER BY CAST("from" AS INTEGER), "from"'
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

      def kept_file_data(name) = stored.kept_file_data(name)

      # The hash of every file printed from the store's rows, by path.
      def printed = stored.printed

      def backups = stored.backups

      # "missing" when the archive's file is gone, "changed" when its sha256
      # no longer matches, nil when it reads back the same.
      def backup_flag(backup) = stored.backup_flag(backup)

      private

      def ensure_backfill!(migrate = true)
        return backfill! if migrate
        return if ReferenceBackfill.complete?(@databases.fetch(:knowledge).path, origin_id)

        raise MaintenanceRequired, "retrieval migration is required before a selected source can be read"
      end

      def references = (@references ||= RetrievalReference.new(@databases, store:, origin: @origin))

      def searcher = (@searcher ||= RetrievalSearch.new(@databases.fetch(:knowledge), origin: @origin))

      def stored = (@stored ||= RetrievalStoreRead.new(@databases))

      def sessions = (@sessions ||= SessionReader.new(@databases, store:, origin: @origin))

      def work = (@work ||= WorkReader.new(@databases, origin: @origin))

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
