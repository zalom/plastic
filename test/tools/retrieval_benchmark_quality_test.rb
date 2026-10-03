# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require_relative "../../tools/retrieval_benchmark"

class RetrievalBenchmarkQualityTest < Minitest::Test
  def test_skips_unexpected_search_rows_when_the_expected_reference_is_not_in_the_top_twenty
    Dir.mktmpdir do |directory|
      input = File.join(directory, "quality.json")
      File.write(input, JSON.generate(quality_fixture_with_distractors))
      report = Plastic::RetrievalBenchmark::QualityEvaluator.new(input, directory).evaluate
      answer = report.fetch("synthetic_top_20").fetch(0)

      assert_equal [false, "not_in_top_20", [], 20], [answer.fetch("passed"), answer.fetch("classification"),
        answer.fetch("passage_checks"), answer.fetch("returned_references").length]
    end
  end

  private

  def quality_fixture_with_distractors
    distractors = 20.times.map do |index|
      { "store" => "store-1", "intent_id" => "d#{index}", "path" => "notes.md", "content" => "fictional search result #{index}" }
    end
    source = { "store" => "store-1", "intent_id" => "source", "path" => "source.md", "content" => "expected evidence" }
    expected = { "store" => "store-1", "intent_id" => "source", "path" => "source.md", "relevant_passage_hint" => "expected evidence" }
    { "status" => "synthetic_fixture", "documents" => distractors + [source],
      "queries" => [{ "id" => "missing-expected", "harness_search_terms" => "fictional", "scope" => ["store-1"], "expected" => [expected] }] }
  end
end
