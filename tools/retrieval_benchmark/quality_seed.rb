# frozen_string_literal: true

require_relative "benchmark_store_seed"

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

      def seed_store(store, rows) = BenchmarkStoreSeed.new(@home, store, rows.map { |row| BenchmarkSeedDocument.from_quality(row) }).seed
    end
  end
end
