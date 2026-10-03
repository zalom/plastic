# frozen_string_literal: true

require "json"

module Plastic
  module RetrievalBenchmark
    # Runs one public top-20 query and checks every returned expected passage.
    class QualityQuery
      def initialize(home, query)
        @home = home
        @query = query
      end

      def evaluate
        expected = expected_references
        sample = Measurements.run_command(search_command)
        rows = JSON.parse(sample.fetch("stdout")).fetch("result").fetch("results")
        checks = rows.filter_map.with_index { |row, index| check(row, expected[row.fetch("uri")], index + 1) }
        answer(expected, sample, rows, checks)
      end

      private

      def expected_references
        @query.fetch("expected").to_h do |row|
          reference = Graph.open(home: @home, store: row.fetch("store")).retrieval.reference(row.fetch("intent_id"), row.fetch("path"))
          [reference.fetch(:uri), row.fetch("relevant_passage_hint") { @query.fetch("relevant_passage_hint") }]
        end
      end

      def check(row, hint, rank)
        passage = fetch_passage(row)
        { "uri" => row.fetch("uri"), "rank" => rank, "position" => row.fetch("position"), "hint" => hint,
          "body" => passage&.fetch("body"), "matched" => passage&.fetch("body")&.include?(hint) || false }
      end

      def answer(expected, sample, rows, checks)
        matched = checks.find { |check| check.fetch("matched") }
        { "id" => @query.fetch("id"), "expected_references" => expected.keys, "returned_references" => rows.map { |row| row.fetch("uri") },
          "command_output_valid" => sample.fetch("output_valid"), "rank" => matched&.fetch("rank"),
          "matched_text" => matched&.fetch("body"), "resolved_qualified_reference" => matched&.fetch("uri"), "passed" => !matched.nil?,
          "classification" => classification(checks, matched), "passage_checks" => checks }
      end

      def fetch_passage(row)
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "document", "get", row.fetch("uri"), "--passage", row.fetch("position").to_s, "--json"]
        sample = Measurements.run_command({ home: @home, argv:, stores: [row.fetch("store")] })
        document = JSON.parse(sample.fetch("stdout")).dig("result", "document")
        document if sample.fetch("exit_status").zero? && document
      end

      def classification(checks, matched)
        return "passage_match" if matched
        return "not_in_top_20" if checks.empty?

        "passage_fetch_failed"
      end

      def search_command
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "search", @query.fetch("harness_search_terms")]
        @query.fetch("scope").each { |store| argv.concat(["--source-project", store]) }
        { home: @home, argv: argv.concat(["--limit", "20", "--json"]), stores: @query.fetch("scope") }
      end
    end
  end
end
