# frozen_string_literal: true

require "forwardable"
require_relative "../command_run"
require_relative "work/session/reader"
require_relative "work/reader"
require_relative "source"
require_relative "knowledge/link"
require_relative "knowledge/archive"
require_relative "evidence/writer"
require_relative "retrieval/errors"
require_relative "retrieval/evidence/integrity"
require_relative "retrieval/index"
require_relative "retrieval/reference"
require_relative "retrieval/search"
require_relative "retrieval/store_read"
require_relative "retrieval/archive_reader"
require_relative "retrieval/structure_reader"
require_relative "retrieval/evidence"

module Plastic
  # Persists and retrieves the graph records that describe Plastic work.
  module Graph
    # Provides ordinary retrieval reads from graph records. These methods do
    # not write. Explicit repair and reindex rebuild derived
    # tables. A selected-source read never runs either operation.
    class RetrievalGraph
      SEARCH_LIMIT = Retrieval::Search::SEARCH_LIMIT
      extend Forwardable

      attr_reader :store, :clock

      def_delegators :sessions, :command_run, :session, :previous_session, :predecessor, :last_run, :touched, :sessions_on
      def_delegators :work, :ready_nodes, :claimed_nodes, :node, :rulings, :links, :every_link
      def_delegators :evidence, :documents, :fetch, :fetch_reference, :fetch_batch, :fetch_passage, :search, :search_current, :repair, :reindex, :search_index_report
      def_delegators "evidence.references", :reference, :search_reference

      def initialize(databases, store:, origin:, clock:)
        @databases = databases
        @store = store
        @origin = origin
        @clock = clock
      end

      def origin_id = @origin.id
      def intents = read(:intents).sort_by(&:segments)

      def intent(intent_id)
        row = @databases.fetch(:store).row("SELECT * FROM intents WHERE intent_id = :intent_id AND origin_id = :origin", intent_id:, origin: origin_id)
        row && Knowledge::Intent.from_h(row)
      end

      def unarchived_intents = intents.reject { |intent| archives.archived?(intent.intent_id) }

      def archived_reference?(reference) = archives.archived?(fetch_reference(reference).fetch(:intent_id))

      def clusters = read(:clusters)

      def stored = (@stored ||= Retrieval::StoreRead.new(@databases, origin_id))

      def archives = (@archives ||= Retrieval::ArchiveReader.new(@databases, origin_id))

      def structure = (@structure ||= Retrieval::StructureReader.new(@databases, origin_id))

      DOCUMENT_SQL = "SELECT * FROM documents WHERE intent_id = :intent_id AND path = :path AND origin_id = :origin"
      SEARCH_SQL = Retrieval::Search::SEARCH_SQL

      private

      def evidence = (@evidence ||= Retrieval::Evidence.new(@databases, store:, origin: @origin))

      def sessions = (@sessions ||= Work::Session::Reader.new(@databases, store:, origin: @origin))

      def work = (@work ||= Work::Reader.new(@databases, origin: @origin))

      def read(name, intent_id = nil) = SOURCES.fetch(name).read(@databases, origin: origin_id, intent_id:)
    end
  end
end
