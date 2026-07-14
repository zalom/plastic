# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/restore_intent_v1"

class RestoreIntentV1LibTest < Minitest::Test
  # A minimal store_index/relocation_map: one store "global" holding ids "1" and "2".
  # "999" is absent from every known store (a confirmed-dead target).
  def store_index
    { "global" => %w[1 2] }
  end

  def empty_relocation_map
    {}
  end

  def test_union_dedupes_and_preserves_both_snapshots
    graph = RestoreIntentV1.compute_graph(
      v1_sources: [], v1_chain: ["1"],
      current_sources: [], current_chain: ["1", "2"],
      referer_store: "global", relocation_map: empty_relocation_map, store_index: store_index
    )
    assert_equal %w[1 2], graph[:chain].sort
    assert_empty graph[:dropped]
  end

  def test_dead_target_is_dropped_and_reported
    graph = RestoreIntentV1.compute_graph(
      v1_sources: [], v1_chain: ["999"],
      current_sources: [], current_chain: ["1"],
      referer_store: "global", relocation_map: empty_relocation_map, store_index: store_index
    )
    assert_equal ["1"], graph[:chain]
    refute_includes graph[:chain], "999"
    assert_equal [{ field: :chain, ref: "999" }], graph[:dropped]
  end

  def test_unknown_store_ref_is_kept_and_flagged_unverified
    graph = RestoreIntentV1.compute_graph(
      v1_sources: [], v1_chain: ["otherstore:5"],
      current_sources: [], current_chain: [],
      referer_store: "global", relocation_map: empty_relocation_map, store_index: store_index
    )
    assert_includes graph[:chain], "otherstore:5"
    assert_equal [{ field: :chain, ref: "otherstore:5" }], graph[:unverified]
    assert_empty graph[:dropped]
  end

  def test_apply_graph_rewrites_only_sources_and_chain
    v1_content = <<~MD
      ---
      id: "1"
      intent: "Example"
      sources: []
      chain: []
      created: 2026-01-01
      author: human
      tags: []
      ---

      ## Intent
      Example.
    MD
    result = RestoreIntentV1.apply_graph(v1_content, desired_sources: [], desired_chain: ["2"])
    assert_includes result, "chain: [\"2\"]"
    assert_includes result, "## Intent\nExample.\n"
  end
end
