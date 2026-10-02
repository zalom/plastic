# frozen_string_literal: true

require "json"
require "rbconfig"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    class QualityEvaluator
      def initialize(input, directory)
        @input = input
        @home = File.join(directory, "quality-home")
      end

      def evaluate
        candidate = JSON.parse(File.read(@input))
        seed(candidate.fetch("documents"))
        answers = candidate.fetch("queries").map { |query| evaluate_query(query) }
        { "status" => candidate.fetch("status"), "owner_review" => { "status" => "pending" }, "synthetic_top_20" => answers,
          "synthetic_recall" => answers.count { |answer| answer.fetch("passed") }.fdiv(answers.length) }
      end

      private

      def seed(documents)
        documents.group_by { |document| document.fetch("store") }.each do |store, rows|
          graphs = Graph.open(home: @home, store:)
          graphs.databases.each_value { |database| database.rows("SELECT 1") }
          writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
          rows.each { |row| writer.write(row.fetch("intent_id"), row.fetch("path"), row.fetch("content")) }
          graphs.retrieval.backfill!
        end
      end

      def evaluate_query(query)
        expected = expected_references(query)
        sample = Measurements.run_command(search_command(query))
        rows = JSON.parse(sample.fetch("stdout")).fetch("result").fetch("results")
        matched = rows.find { |row| expected.include?(row.fetch("uri")) && row.fetch("body").include?(query.fetch("relevant_passage_hint")) }
        { "id" => query.fetch("id"), "expected_references" => expected, "rank" => matched && rows.index(matched) + 1,
          "matched_text" => matched&.fetch("body"), "resolved_qualified_reference" => matched&.fetch("uri"),
          "returned_references" => rows.map { |row| row.fetch("uri") }, "passed" => !matched.nil?, "command_output_valid" => sample.fetch("output_valid") }
      end

      def expected_references(query)
        query.fetch("expected").map do |row|
          Graph.open(home: @home, store: row.fetch("store")).retrieval.reference(row.fetch("intent_id"), row.fetch("path")).fetch(:uri)
        end
      end

      def search_command(query)
        argv = [RbConfig.ruby, File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "search", query.fetch("harness_search_terms")]
        query.fetch("scope").each { |store| argv.concat(["--source-project", store]) }
        argv.concat(["--limit", "20", "--json"])
        { home: @home, argv:, stores: query.fetch("scope") }
      end
    end
  end
end
