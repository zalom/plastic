# frozen_string_literal: true

require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    # Identifies one text document to add to an isolated benchmark store.
    BenchmarkSeedDocument = Data.define(:intent_id, :path, :body) do
      def self.from_quality(row) = new(row.fetch("intent_id"), row.fetch("path"), row.fetch("content"))
      def self.from_file(path, index) = new((index + 1).to_s, File.basename(path), File.read(path, encoding: "UTF-8"))
    end

    # Opens, initializes, and backfills one isolated benchmark store.
    class BenchmarkStoreSeed
      def initialize(home, store, documents)
        @home = home
        @store = store
        @documents = documents
      end

      def seed
        initialize_databases
        write_documents
        retrieval.backfill
      end

      private

      def graphs = (@graphs ||= Graph.open(home: @home, store: @store))
      def databases = graphs.databases
      def retrieval = graphs.retrieval
      def initialize_databases = databases.each_value { |database| database.rows("SELECT 1") }

      def write_documents
        writer = Graph::EvidenceWriter.new(databases.fetch(:knowledge), retrieval.origin_id)
        @documents.each { |document| writer.write(*document.deconstruct) }
      end
    end
  end
end
