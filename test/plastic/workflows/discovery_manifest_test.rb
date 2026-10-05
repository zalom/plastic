# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/discovery_manifest"

class DiscoveryManifestTest < Plastic::TestCase
  def build(terms, scope = ["global"]) = Plastic::Workflows::DiscoveryManifest.build(call_context(intent_id: "1", terms:), scope)

  def test_the_manifest_names_the_request_and_its_candidates
    open_intent

    manifest = build("alpha")

    assert_equal ["1", "alpha", ["global"]], manifest.values_at(:intent_id, :query, :scope)
    assert_equal ["global"], manifest.fetch(:candidates).map { |row| row.fetch("store") }
  end

  def test_the_manifest_hands_the_agent_its_commands
    open_intent

    assert_equal "plastic intent context 1 --from FILE --project global", build("alpha").dig(:workflow, "context")
  end

  def test_a_source_missing_a_graph_file_needs_maintenance
    error = assert_raises(Plastic::Graph::RetrievalGraph::MaintenanceRequired) { build("alpha", ["other"]) }

    assert_equal "retrieval maintenance is required before source other can be read", error.message
  end
end
