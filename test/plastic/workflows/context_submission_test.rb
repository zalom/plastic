# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/context_submission"

class ContextSubmissionTest < Plastic::TestCase
  Source = Struct.new(:graph) do
    def retrieval(_reference) = graph
  end

  EMPTY = { "facts" => [], "interpretations" => [], "gaps" => [], "rulings" => [] }.freeze

  def setup
    super
    @reference = retrieval.reference("1", open_intent.file).fetch(:uri)
  end

  def validate(submission, candidates: [@reference])
    discovery = { "query" => "alpha", "scope" => ["global"], "candidates" => candidates.map { |uri| { "uri" => uri } } }
    path = File.join(@home, "submission.json")
    File.write(path, JSON.generate(submission))
    Plastic::Workflows::ContextSubmission.new(intent_id: "1", discovery:, source: Source.new(retrieval)).validate(path)
  end

  def test_a_valid_submission_keeps_its_categories_and_unique_evidence
    result = validate(EMPTY.merge("evidence" => [@reference, @reference]))

    assert_equal [[@reference], { @reference => false }], result.values_at("evidence", "archive_states")
    assert_equal({ "query" => "alpha", "scope" => ["global"] }, result.fetch("discovery"))
  end

  def test_a_submission_that_is_not_an_object_is_a_usage_error
    error = assert_raises(Plastic::CLI::Command::Usage) { validate([]) }

    assert_equal "context submission must be a JSON object", error.message
  end

  def test_a_missing_category_raises
    assert_raises(KeyError) { validate({ "evidence" => [] }) }
  end

  def test_a_category_that_is_not_a_list_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { validate(EMPTY.merge("evidence" => [], "facts" => "one")) }
  end

  def test_evidence_that_was_not_discovered_fails
    error = assert_raises(Plastic::CLI::Command::Failure) { validate(EMPTY.merge("evidence" => [@reference]), candidates: []) }

    assert_equal "evidence was not discovered: #{@reference}", error.message
  end

  def test_evidence_named_without_its_current_revision_fails
    old = @reference.split("?").first

    error = assert_raises(Plastic::CLI::Command::Failure) { validate(EMPTY.merge("evidence" => [old]), candidates: [old]) }

    assert_equal "evidence revision changed: #{old}", error.message
  end
end
