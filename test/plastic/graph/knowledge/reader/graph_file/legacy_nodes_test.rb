# frozen_string_literal: true

require_relative "../../../../../test_helper"
require_relative "../../../../../../lib/plastic/graph/knowledge/reader"

class LegacyNodesTest < Minitest::Test
  UPDATED = "2026-10-20T08:00:00Z"

  def node(id, **fields) = { "id" => id, "state" => "done", "updated_at" => UPDATED }.merge(fields.transform_keys(&:to_s))

  def convert(*nodes, **data) = Plastic::Graph::Knowledge::Reader::GraphFile::LegacyNodes.new({ "nodes" => nodes }.merge(data.transform_keys(&:to_s))).call

  def test_a_file_without_old_fields_is_returned_as_it_is
    data = { "nodes" => [node("n1")] }

    assert_same data, Plastic::Graph::Knowledge::Reader::GraphFile::LegacyNodes.new(data).call
  end

  def test_a_done_node_with_a_worker_gets_one_closed_run
    result = convert(node("n1", by: "s-1", retries: 2))

    assert_equal [{ "node_id" => "n1", "number" => 1, "agent" => "", "session_id" => "s-1", "started_at" => UPDATED, "ended_at" => UPDATED, "result" => "done" }], result["runs"]
    assert_equal [node("n1")], result["nodes"]
  end

  def test_an_open_node_with_a_worker_gets_a_released_run
    assert_equal "released", convert(node("n1", state: "open", by: "s-1"))["runs"].first["result"]
  end

  def test_a_claimed_node_keeps_its_claim_and_its_run_stays_open
    result = convert(node("n1", state: "claimed", by: "s-1"))

    assert_equal [nil, nil], result["runs"].first.values_at("ended_at", "result")
    assert_equal ["s-1", UPDATED], result["nodes"].first.values_at("claimed_by", "claimed_at")
  end

  def test_a_node_without_a_worker_gives_no_run_and_loses_its_old_fields
    result = convert(node("n1", by: nil, retries: 3))

    assert_equal [[], [node("n1")]], [result["runs"], result["nodes"]]
  end

  def test_the_runs_already_in_the_file_stay_and_a_node_that_is_no_hash_is_skipped
    result = convert("stray", node("n1", by: "s-1"), runs: [{ "node_id" => "n0" }])

    assert_equal %w[n0 n1], result["runs"].map { |run| run["node_id"] }
  end
end
