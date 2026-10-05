# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/search"
require_relative "../../../scripts/lib/plastic/graph/retrieval/evidence/writer"

class WorkflowSearchTest < Plastic::TestCase
  def search(source_projects)
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "empty"))
    run_workflow(Plastic::Workflows::Search, harness: scoped_harness(slug: "global"), source_projects:, terms: "falcon", limit: "5")
  end

  def test_the_found_passages_are_printed_as_results
    open_intent
    Plastic::Graph::Retrieval::Evidence::Writer.new(store_graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", "falcon wings")
    retrieval.backfill

    outcome, context = search([])

    assert_equal [:done, ["evidence.md"]], [outcome, printed_row(context, "results").map { |row| row.fetch("path") }]
  end

  def test_a_store_without_its_databases_fails_the_call
    outcome, = search(["empty"])

    assert_equal "code_search, gate: retrieval maintenance is required before source empty can be read", outcome.message
  end
end
