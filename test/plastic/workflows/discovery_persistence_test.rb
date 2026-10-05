# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/discovery_persistence"

class DiscoveryPersistenceTest < Plastic::TestCase
  DOCUMENT = { "query" => "alpha", "candidates" => [] }.freeze

  def persist = Plastic::Workflows::DiscoveryPersistence.persist(call_context(intent_id: "1"), DOCUMENT)

  def test_the_manifest_is_written_as_a_row
    persist
    row = store_graphs.databases[:knowledge].row("SELECT data FROM retrieval_discoveries WHERE intent_id = '1'")

    assert_equal DOCUMENT, JSON.parse(row.fetch("data"))
  end

  def test_the_manifest_replaces_the_file_of_the_store
    write("discovery/1.json", "{}")
    persist

    assert_equal DOCUMENT, JSON.parse(File.read(store_path("discovery/1.json")))
  end
end
