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
require_relative "retrieval_roadmap_reads"
require_relative "retrieval_store_reads"
require_relative "retrieval_archive_reads"
require_relative "retrieval_structure_reads"
require_relative "exact_lookup_plans"
require_relative "retrieval_evidence"

module Plastic
  # Persists and retrieves the graph records that describe Plastic work.
  module Graph
    # Provides ordinary retrieval reads from graph records. These methods do
    # not write. Explicit owning-store backfill and repair rebuild derived
    # tables. A selected-source read never runs either operation.
    class RetrievalGraph
      include RetrievalRoadmapReads
      include RetrievalStoreReads
      include RetrievalArchiveReads
      include RetrievalStructureReads

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
      def_delegators :evidence, :documents, :fetch, :fetch_reference, :fetch_batch, :fetch_passage, :search, :search_current, :backfill, :repair
      def_delegators "evidence.references", :reference, :search_reference

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

      def exact_lookup_plans(intent_id, path) = ExactLookupPlans.new(@databases, origin_id).rows(intent_id, path)

      DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"
      SEARCH_SQL = RetrievalSearch::SEARCH_SQL

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
