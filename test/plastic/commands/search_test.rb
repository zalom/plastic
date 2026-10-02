# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/search"
require_relative "../../../scripts/lib/plastic/graph/evidence_writer"

class SearchTest < Plastic::TestCase
  def test_searches_loaded_sources_and_explicit_scope_replaces_them
    write_document("global", "global evidence")
    write_document("other", "other evidence")

    loaded = plastic("search", "evidence", "--json", env: { "PLASTIC_SOURCE_PROJECTS" => "global, other" }, table: Plastic::CLI::TABLE)
    explicit = plastic("search", "evidence", "--source-project", "other", "--json", env: { "PLASTIC_SOURCE_PROJECTS" => "global" }, table: Plastic::CLI::TABLE)

    assert_equal 0, loaded.code
    assert_includes loaded.out, "global"
    assert_includes loaded.out, "other"
    refute_includes explicit.out, "global"
    assert_includes explicit.out, "other"
  end

  private

  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
  end
end
