# frozen_string_literal: true

require "json"
require_relative "quality_passage_checks"

module Plastic
  module RetrievalBenchmark
    # Resolves one fixture row to a qualified reference and expected hint.
    QualityExpectedEvidence = Data.define(:store, :intent_id, :path, :hint) do
      def self.from(row, fallback)
        new(row.fetch("store"), row.fetch("intent_id"), row.fetch("path"), row.fetch("relevant_passage_hint", fallback))
      end

      def reference(home) = Graph.open(home:, store:).retrieval.reference(intent_id, path).fetch(:uri)
    end

    # Projects a public search response and its passage checks into one answer.
    QualityQueryResult = Data.define(:id, :expected, :sample, :rows, :checks) do
      def answer
        base_answer.merge(match_answer)
      end

      private

      def base_answer
        { "id" => id, "expected_references" => expected.keys, "returned_references" => rows.map { |row| row.fetch("uri") },
          "command_output_valid" => sample.fetch("output_valid"), "passage_checks" => checks }
      end

      def match_answer
        matched = checks.find { |check| check.fetch("matched") }
        return QualityMatchedAnswer.new(matched).build if matched

        unmatched_answer
      end

      def unmatched_answer
        { "rank" => nil, "matched_text" => nil, "resolved_qualified_reference" => nil, "passed" => false,
          "classification" => checks.empty? ? "not_in_top_20" : "passage_fetch_failed" }
      end
    end

    # Projects one matching bounded passage into a successful answer.
    QualityMatchedAnswer = Data.define(:matched) do
      def build
        { "rank" => matched.fetch("rank"), "matched_text" => matched.fetch("body"), "resolved_qualified_reference" => matched.fetch("uri"),
          "passed" => true, "classification" => "passage_match" }
      end
    end

    # Builds the shipped public top-20 command from one loaded query.
    QualitySearchCommand = Data.define(:home, :query) do
      def build
        scope = query.fetch("scope")
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "search", query.fetch("harness_search_terms")]
        scope.each { |store| argv.concat(["--source-project", store]) }
        { home:, argv: argv.concat(["--limit", "20", "--json"]), stores: scope }
      end
    end

    # Runs one public top-20 query and checks every returned expected passage.
    class QualityQuery
      def initialize(home, query)
        @home = home
        @query = query
      end

      def evaluate
        expected = expected_references
        sample = Measurements.run_command(QualitySearchCommand.new(@home, @query).build)
        rows = JSON.parse(sample.fetch("stdout")).fetch("result").fetch("results")
        checks = QualityPassageChecks.new(@home, expected).evaluate(rows)
        QualityQueryResult.new(@query.fetch("id"), expected, sample, rows, checks).answer
      end

      private

      def expected_references
        @query.fetch("expected").to_h do |row|
          evidence = QualityExpectedEvidence.from(row, @query.fetch("relevant_passage_hint", nil))
          [evidence.reference(@home), evidence.hint]
        end
      end
    end
  end
end
