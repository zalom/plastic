# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/document/batch"

class BatchDocumentsTest < Plastic::TestCase
  def write_document(path, body)
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:store), origin, clock: FixedClock::CLOCK).write("1", path, body)
    retrieval.repair
    retrieval.reference("1", path).fetch(:uri)
  end

  def fetch(references) = run_workflow(Plastic::Workflows::Code::Document::Batch, references:)

  def test_the_documents_come_back_in_the_order_asked
    first = write_document("a.md", "first")
    second = write_document("b.md", "second")

    outcome, context = fetch("#{second} #{first}")

    assert_equal :done, outcome
    assert_equal %w[second first], printed_row(context, "documents").map { |document| document.fetch(:body) }
  end

  def test_a_missing_document_fails_the_call
    write_document("a.md", "first")

    assert_raises(Plastic::Failed) { fetch("plastic://global/1/missing.md") }
  end

  def test_an_unknown_store_fails_the_call
    error = assert_raises(Plastic::Failed) { fetch("plastic://nowhere/1/a.md") }

    assert_equal "no project named \"nowhere\"", error.message
  end
end
