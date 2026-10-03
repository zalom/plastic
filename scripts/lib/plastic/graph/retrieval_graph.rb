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
require_relative "retrieval_archive_reader"
require_relative "retrieval_roadmap_reader"
require_relative "retrieval_evidence"

module Plastic
  # Persists and retrieves the graph records that describe Plastic work.
  module Graph
    # The read side of the graphs: every check reads from here. Every method
    # returns records or plain values. Nothing here writes. A method that
    # takes an intent id reads every intent of the store when given none.
    class RetrievalGraph
      # Signals that a caller must build the derived retrieval rows first.
      class MaintenanceRequired < StandardError; end
      # Signals an invalid or unavailable document or passage reference.
      class MissingReference < StandardError; end
      # Signals an FTS query that SQLite rejected.
      class InvalidSearch < StandardError; end
      SEARCH_LIMIT = RetrievalSearch::SEARCH_LIMIT
      extend Forwardable

      attr_reader :store

      def_delegators :sessions, :routine_run, :session, :previous_session, :predecessor, :locks_of, :lock, :last_run, :touched
      def_delegators :work, :ready_nodes, :node, :rulings, :links
      def_delegators :evidence, :documents, :fetch, :reference, :fetch_reference, :fetch_batch, :fetch_passage, :exact_lookup_plans, :search, :search_reference, :backfill!, :repair!

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

      DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"
      SEARCH_SQL = RetrievalSearch::SEARCH_SQL

      def savepoints(intent_id = nil) = read(:savepoints, intent_id)

      def nodes(intent_id = nil) = read(:nodes, intent_id)

      def edges(intent_id = nil) = read(:edges, intent_id)

      LINKING_SQL = "SELECT * FROM links WHERE origin_id = :origin AND (to_ref = :id OR to_ref LIKE :prefix)"

      # Links whose to_ref is `id` or a ruling of it, such as "ID/D1".
      def linking(id)
        @databases.fetch(:knowledge).rows(LINKING_SQL, origin: origin_id, id:, prefix: "#{id}/%").map { |row| Link.from_h(row) }
      end

      # The intent's archive row, or nil when it was never archived.
      def archive_of(intent_id) = archives.archive_of(intent_id)

      # True while the intent has an archive row with no restored_at.
      def archived?(intent_id)
        archives.archived?(intent_id)
      end

      # One roadmap by slug, or nil when none has been started.
      def roadmap(slug) = roadmaps.roadmap(slug)
      def batches(slug) = roadmaps.batches(slug)
      def roadmap_items(slug) = roadmaps.items(slug)
      def roadmap_edges(slug) = roadmaps.edges(slug)
      def roadmap_log(slug) = roadmaps.log(slug)

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

      def evidence = (@evidence ||= RetrievalEvidence.new(@databases, store:, origin: @origin))

      def stored = (@stored ||= RetrievalStoreRead.new(@databases))

      def archives = (@archives ||= RetrievalArchiveReader.new(@databases.fetch(:work), origin_id))

      def roadmaps = (@roadmaps ||= RetrievalRoadmapReader.new(@databases.fetch(:work), origin_id))

      def sessions = (@sessions ||= SessionReader.new(@databases, store:, origin: @origin))

      def work = (@work ||= WorkReader.new(@databases, origin: @origin))

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
