# frozen_string_literal: true

require_relative "../../test_helper"

class IntentDiscoverTest < Plastic::TestCase
  def test_records_deterministic_selected_source_candidates
    write_document("global", "global evidence")
    write_document("other", "other evidence")

    result = plastic("intent", "discover", "1", "evidence", "--source-project", "other", "--source-project", "global", "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    document = JSON.parse(result.out)
    manifest = document.fetch("result").fetch("discovery")
    assert_equal "1", manifest.fetch("intent_id")
    assert_equal "evidence", manifest.fetch("query")
    assert_equal %w[global other], manifest.fetch("scope")
    assert_equal %w[global other], manifest.fetch("candidates").map { |candidate| candidate.fetch("store") }
    assert manifest.fetch("candidates").all? { |candidate| candidate.key?("uri") && candidate.key?("revision") && candidate.key?("archived") }
    assert_equal manifest, JSON.parse(File.read(store_path("discovery/1.json")))
  end

  private

  def write_document(store, body)
    graphs = Plastic::Graph.open(home: @plastic_home, store:)
    Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), origin).write("1", "evidence.md", body)
    graphs.retrieval.backfill!
  end
end
