# frozen_string_literal: true

require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    # Seeds isolated stores with the immutable documents used by the quality fixture.
    class QualitySeed
      def initialize(home) = @home = home

      def seed(documents)
        documents.group_by { |document| document.fetch("store") }.each do |store, rows|
          seed_store(store, rows)
        end
      end

      private

      def seed_store(store, rows)
        graphs = Graph.open(home: @home, store:)
        databases = graphs.databases
        databases.each_value { |database| database.rows("SELECT 1") }
        writer = Graph::EvidenceWriter.new(databases.fetch(:knowledge), graphs.retrieval.origin_id)
        rows.each { |row| writer.write(row.fetch("intent_id"), row.fetch("path"), row.fetch("content")) }
        graphs.retrieval.backfill
      end
    end
  end
end
