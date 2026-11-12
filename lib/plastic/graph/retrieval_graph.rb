# frozen_string_literal: true

require "forwardable"
require_relative "../routine_run"
require_relative "work/session/reader"
require_relative "work/reader"
require_relative "source"
require_relative "knowledge/link"
require_relative "knowledge/roadmap"
require_relative "knowledge/archive"
require_relative "knowledge/backup"
require_relative "retrieval/evidence/writer"
require_relative "retrieval/evidence/integrity"
require_relative "retrieval/reference_backfill"
require_relative "retrieval/reference"
require_relative "retrieval/search"
require_relative "retrieval/store_read"
require_relative "retrieval/archive_reader"
require_relative "retrieval/roadmap_reader"
require_relative "retrieval/roadmap_reads"
require_relative "retrieval/store_reads"
require_relative "retrieval/archive_reads"
require_relative "retrieval/structure_reads"
require_relative "retrieval/evidence"

module Plastic
  # Persists and retrieves the graph records that describe Plastic work.
  module Graph
    # Provides ordinary retrieval reads from graph records. These methods do
    # not write. Explicit owning-store backfill and repair rebuild derived
    # tables. A selected-source read never runs either operation.
    class RetrievalGraph
      include Retrieval::RoadmapReads
      include Retrieval::StoreReads
      include Retrieval::ArchiveReads
      include Retrieval::StructureReads

      # Signals that a caller must build the derived retrieval rows first.
      class MaintenanceRequired < StandardError
        attr_reader :slug

        def initialize(message = nil, slug: nil)
          super(message)
          @slug = slug
        end
      end

      # Signals an invalid or unavailable document or passage reference.
      class MissingReference < StandardError; end
      # Signals an FTS query that SQLite rejected.
      class InvalidSearch < StandardError; end
      SEARCH_LIMIT = Retrieval::Search::SEARCH_LIMIT
      extend Forwardable

      attr_reader :store

      def_delegators :sessions, :routine_run, :session, :previous_session, :predecessor, :locks_of, :lock, :liveness, :last_run, :touched
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
        row && Knowledge::Intent.from_h(row)
      end

      def unarchived_intents = intents.reject { |intent| archived?(intent.intent_id) }

      def completion(intent_id)
        @databases.fetch(:work).row("SELECT * FROM completions WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id)
      end

      def clusters = read(:clusters)

      DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"
      SEARCH_SQL = Retrieval::Search::SEARCH_SQL

      private

      def evidence = (@evidence ||= Retrieval::Evidence.new(@databases, store:, origin: @origin))

      def stored = (@stored ||= Retrieval::StoreRead.new(@databases))

      def archives = (@archives ||= Retrieval::ArchiveReader.new(@databases.fetch(:work), origin_id))

      def roadmaps = (@roadmaps ||= Retrieval::RoadmapReader.new(@databases.fetch(:work), origin_id))

      def sessions = (@sessions ||= Work::Session::Reader.new(@databases, store:, origin: @origin))

      def work = (@work ||= Work::Reader.new(@databases, origin: @origin))

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
