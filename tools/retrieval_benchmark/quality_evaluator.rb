# frozen_string_literal: true

require "json"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph"
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
        documents.group_by { |document| document.fetch("store") }.each { |store, rows| seed_store(store, rows) }
      end

      def seed_store(store, rows)
        graphs = Graph.open(home: @home, store:)
        graphs.databases.each_value { |database| database.rows("SELECT 1") }
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        rows.each { |row| writer.write(row.fetch("intent_id"), row.fetch("path"), row.fetch("content")) }
        graphs.retrieval.backfill!
      end

      def evaluate_query(query)
        expected = expected_references(query)
        sample, rows = search_rows(query)
        matched = matching_row(rows, expected)
        passage = matched && fetch_passage(matched)
        query_result(query, { expected:, sample:, rows:, matched:, passage: })
      end

      def query_result(query, result)
        match = match_metadata(result)
        { "id" => query.fetch("id"), "expected_references" => result.fetch(:expected).map { |row| row.fetch("uri") },
          "returned_references" => result.fetch(:rows).map { |row| row.fetch("uri") }, "command_output_valid" => result.fetch(:sample).fetch("output_valid"), **match }
      end

      def match_metadata(result)
        matched = result.fetch(:matched)
        passage = result.fetch(:passage)
        { "rank" => matched && result.fetch(:rows).index(matched) + 1, "matched_text" => passage&.fetch("body"),
          "resolved_qualified_reference" => matched&.fetch("uri"), "passed" => !passage.nil?,
          "classification" => classification(matched, passage) }
      end

      def search_rows(query)
        sample = Measurements.run_command(search_command(query))
        [sample, JSON.parse(sample.fetch("stdout")).fetch("result").fetch("results")]
      end

      def matching_row(rows, expected)
        rows.find do |row|
          candidate = expected.find { |item| item.fetch("uri") == row.fetch("uri") }
          candidate && row.fetch("body").include?(candidate.fetch("hint"))
        end
      end

      def fetch_passage(row)
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "document", "get", row.fetch("uri"), "--passage", row.fetch("position").to_s, "--json"]
        sample = Measurements.run_command({ home: @home, argv:, stores: [row.fetch("store")] })
        document = JSON.parse(sample.fetch("stdout")).dig("result", "document")
        document if sample.fetch("exit_status").zero? && document
      end

      def classification(row, passage)
        return "not_in_top_20" unless row
        return "passage_fetch_failed" unless passage

        "passage_match"
      end

      def expected_references(query)
        query.fetch("expected").map do |row|
          { "uri" => Graph.open(home: @home, store: row.fetch("store")).retrieval.reference(row.fetch("intent_id"), row.fetch("path")).fetch(:uri),
            "hint" => row.fetch("relevant_passage_hint") { query.fetch("relevant_passage_hint") } }
        end
      end

      def search_command(query)
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "search", query.fetch("harness_search_terms")]
        query.fetch("scope").each { |store| argv.concat(["--source-project", store]) }
        argv.concat(["--limit", "20", "--json"])
        { home: @home, argv:, stores: query.fetch("scope") }
      end
    end
  end
end
