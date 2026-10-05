# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/batch_documents"

class BatchDocumentsTest < Plastic::TestCase
  def write_document(path, body)
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:knowledge), origin).write("1", path, body)
    retrieval.backfill
    retrieval.reference("1", path).fetch(:uri)
  end

  def fetch(references) = run_workflow(Plastic::Workflows::BatchDocuments, references:)

  def test_the_documents_come_back_in_the_order_asked
    first = write_document("a.md", "first")
    second = write_document("b.md", "second")

    outcome, context = fetch("#{second} #{first}")

    assert_equal :done, outcome
    assert_equal %w[second first], printed_row(context, "documents").map { |document| document.fetch(:body) }
  end

  def test_a_missing_document_fails_the_call
    write_document("a.md", "first")

    outcome, = fetch("plastic://global/1/missing.md")

    assert_kind_of Plastic::Failed, outcome
  end

  def test_an_unknown_store_fails_the_call
    outcome, = fetch("plastic://nowhere/1/a.md")

    assert_equal "code_batch_documents, gate: no project named \"nowhere\"", outcome.message
  end
end
