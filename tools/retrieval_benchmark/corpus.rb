# frozen_string_literal: true

require "fileutils"
require_relative "corpus_documents"

module Plastic
  module RetrievalBenchmark
    # Generates deterministic public documents for retrieval benchmarks.
    class Corpus
      def initialize(directory, target_bytes, stores)
        @directory = directory
        @target_bytes = target_bytes
        @stores = stores
      end

      def generate
        FileUtils.mkdir_p(@directory)
        paths = @stores.times.flat_map { |index| CorpusStoreDocuments.new(@directory, index, bytes_for_store(index)).write }
        CorpusReceipt.new(paths).to_h
      end

      private

      def bytes_for_store(index) = @target_bytes / @stores + ((index < @target_bytes % @stores) ? 1 : 0)
    end
  end
end
