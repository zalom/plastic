# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/submit_context"
require_relative "../../../scripts/lib/plastic/workflows/discover_retrieval"

class SubmitContextTest < Plastic::TestCase
  EMPTY = { "facts" => [], "interpretations" => [], "gaps" => [], "rulings" => [] }.freeze

  def setup
    super
    @reference = retrieval.reference("1", open_intent.file).fetch(:uri)
  end

  def discovered = run_workflow(Plastic::Workflows::DiscoverRetrieval, intent_id: "1", terms: "alpha", source_projects: [])

  def submit(submission)
    path = File.join(@home, "submission.json")
    File.write(path, submission.is_a?(String) ? submission : JSON.generate(submission))
    run_workflow(Plastic::Workflows::SubmitContext, intent_id: "1", from: path)
  end

  def test_a_valid_submission_is_saved_and_printed
    discovered

    outcome, context = submit(EMPTY.merge("evidence" => [@reference]))

    assert_equal [:done, [@reference]], [outcome, printed_row(context, "context").fetch("evidence")]
  end

  def test_a_submission_that_is_not_json_is_a_usage_error
    discovered

    assert_raises(Plastic::CLI::Command::Usage) { submit("not json") }
  end

  def test_a_submission_missing_a_category_fails_the_call
    discovered

    assert_kind_of Plastic::Failed, submit({ "evidence" => [] }).first
  end

  def test_a_submission_without_a_discovery_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { submit(EMPTY.merge("evidence" => [])) }
  end
end
