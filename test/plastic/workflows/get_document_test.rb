# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/get_document"

class GetDocumentTest < Plastic::TestCase
  def setup
    super
    @reference = retrieval.reference("1", open_intent.file).fetch(:uri)
  end

  def get(reference, passage: nil) = run_workflow(Plastic::Workflows::GetDocument, reference:, passage:)

  def test_a_document_is_read_by_its_reference
    outcome, context = get(@reference)

    assert_equal [:done, @reference], [outcome, printed_row(context, "document").fetch(:uri)]
  end

  def test_one_passage_of_a_document_is_read
    _outcome, context = get(@reference, passage: "1")

    assert_equal 1, printed_row(context, "document").fetch(:position)
  end

  def test_a_passage_that_is_not_a_positive_number_is_a_usage_error
    assert_raises(Plastic::CLI::Command::Usage) { get(@reference, passage: "0") }
  end

  def test_a_missing_document_fails_the_call
    outcome, = get("plastic://global/1/missing.md")

    assert_kind_of Plastic::Failed, outcome
  end
end
