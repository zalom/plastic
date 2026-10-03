# frozen_string_literal: true

require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    # Seeds isolated stores and command specifications for benchmark measurement.
    class Seeder
      def initialize(directory, corpus)
        @home = File.join(directory, "home")
        @corpus = corpus
      end

      def seed
        stores.each { |store, paths| seed_store(store, paths) }
        reference = Graph.open(home: @home, store: stores.keys.first).retrieval.reference("1", File.basename(stores.values.first.first))
        { home: @home, reference:, commands: commands(reference) }
      end

      private

      def stores = @corpus.fetch("files").group_by { |path| File.basename(File.dirname(path)) }

      def seed_store(store, paths)
        graphs = Graph.open(home: @home, store:)
        graphs.databases.each_value { |database| database.rows("SELECT 1") }
        seed_documents(graphs, paths)
        graphs.retrieval.backfill
      end

      def seed_documents(graphs, paths)
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        paths.each_with_index { |path, index| writer.write((index + 1).to_s, File.basename(path), File.read(path, encoding: "UTF-8")) }
      end

      def commands(reference)
        executable = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic")]
        stores = %w[store-1 store-2 store-3]
        first = stores.first
        { "exact_lookup" => command([*executable, "document", "get", reference.fetch(:uri), "--json"], reference:),
          "single_store_top_20" => command([*executable, "search", "common", "--source-project", first, "--limit", "20", "--json"], stores: [first]),
          "three_store_rrf_top_20" => command([*executable, "search", "common", *stores.flat_map { |store| ["--source-project", store] }, "--limit", "20", "--json"], stores:) }
      end

      def command(argv, reference: nil, stores: nil) = { home: @home, argv:, reference:, stores: }.compact
    end
  end
end
