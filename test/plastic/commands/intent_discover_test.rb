# frozen_string_literal: true

require_relative "../../test_helper"

class IntentDiscoverTest < Plastic::TestCase
  def test_records_deterministic_selected_source_candidates
    result = plastic("intent", "discover", "1", "evidence", "--json", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    document = JSON.parse(result.out)
    manifest = document.fetch("result").fetch("discovery")
    assert_equal "1", manifest.fetch("intent_id")
    assert_equal "evidence", manifest.fetch("query")
    assert_equal ["global"], manifest.fetch("scope")
    assert_equal manifest, JSON.parse(File.read(store_path("discovery/1.json")))
  end
end
