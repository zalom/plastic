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

  def test_fuses_canonical_selected_sources_with_stable_rrf_order
    write_document("global", "global evidence", path: "z.md")
    write_document("other", "other evidence", path: "a.md")
    write_document("third", "third evidence", path: "m.md")

    result = plastic("search", "evidence", "--source-project", "third", "--source-project", " global ",
      "--source-project", "third", "--source-project", "other", "--json", table: Plastic::CLI::TABLE)
    document = JSON.parse(result.out)
    rows = document.fetch("result").fetch("results")

    assert_equal 0, result.code
    assert_equal %w[global other third], rows.map { |row| row.fetch("store") }
    assert_equal [1, 1, 1], rows.map { |row| row.fetch("local_rank") }
    assert_equal [1.0 / 61, 1.0 / 61, 1.0 / 61], rows.map { |row| row.fetch("rrf_score") }
  end

  def test_rejects_invalid_and_excessive_limits
    %w[0 101 word].each do |limit|
      result = plastic("search", "evidence", "--limit", limit, table: Plastic::CLI::TABLE)

      assert_equal 1, result.code
      assert_match(/limit/, result.err)
    end
  end

  private

  def write_document(store, body, path: "evidence.md")
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", path, body)
    graphs.retrieval.backfill!
  end
end
