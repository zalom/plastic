# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/graph_rebuild"

# ACTION 2 — pure per-intent rebuild transform tests. Hermetic: injected in-memory
# node maps, no file IO, no eval, no ENV.
class GraphRebuildTransformTest < Minitest::Test
  def rebuild(nodes, store: "project:plastic", relocation_map: {}, store_index: {})
    GraphRebuild.rebuild_store(nodes, referer_store: store,
                                      relocation_map: relocation_map,
                                      store_index: store_index)
  end

  # --- dedupe (AC) ---

  def test_dedupe_sources_and_chain_order_preserving
    nodes = { "5" => { sources: %w[3 1 3 2], chain: %w[7 7 9] } }
    result = rebuild(nodes, store_index: { "project:plastic" => %w[5 3 1 2 7 9] })
    assert_equal %w[3 1 2], result[:nodes]["5"][:sources]
    assert_equal %w[7 9], result[:nodes]["5"][:chain]
    assert(result[:changes].any? { |c| c[:kind] == :dedupe && c[:intent] == "5" })
  end

  # --- I3 (AC): overlap kept in sources, dropped from chain, logged ---

  def test_i3_overlap_kept_in_sources_dropped_from_chain_and_logged
    nodes = { "5" => { sources: %w[3], chain: %w[3 9] } }
    result = rebuild(nodes, store_index: { "project:plastic" => %w[5 3 9] })
    assert_equal %w[3], result[:nodes]["5"][:sources]
    assert_equal %w[9], result[:nodes]["5"][:chain]
    i3 = result[:changes].select { |c| c[:kind] == :i3 }
    assert_equal 1, i3.size
    assert_equal "3", i3.first[:before]
  end

  # --- I1 (AC): in-store source gets this intent in its chain, order-preserving ---

  def test_i1_backlink_appended_order_preserving
    nodes = {
      "3" => { sources: [], chain: %w[8] },
      "5" => { sources: %w[3], chain: [] },
    }
    result = rebuild(nodes, store_index: { "project:plastic" => %w[3 5 8] })
    assert_equal %w[8 5], result[:nodes]["3"][:chain]
    bl = result[:changes].select { |c| c[:kind] == :i1_backlink }
    assert_equal 1, bl.size
    assert_equal "3", bl.first[:intent]
    assert_equal "5", bl.first[:backlink]
  end

  # --- I2 NEGATIVE (mandatory AC): relational chain entry NOT removed, no
  #     reciprocal source synthesized ---

  def test_i2_relational_chain_entry_preserved_and_no_reciprocal_source
    # 5.chain lists 9 (a leads-forward edge); 9 does NOT list 5 in sources. The
    # relational chain entry must survive, and 9 must gain no reciprocal source.
    nodes = {
      "5" => { sources: [], chain: %w[9] },
      "9" => { sources: [], chain: [] },
    }
    result = rebuild(nodes, store_index: { "project:plastic" => %w[5 9] })
    assert_equal %w[9], result[:nodes]["5"][:chain], "relational chain entry must survive"
    assert_equal [], result[:nodes]["9"][:sources], "no reciprocal source may be synthesized"
    refute(result[:changes].any? { |c| c[:intent] == "9" && c[:kind] != :dedupe })
  end

  # --- cross-store resolve (AC named hazards) ---

  def relocation_map
    GraphRebuild.build_relocation_map(
      "global" => <<~MD,
        ## Relocated
        - global:14a → project:19a, global:24 → project:22c
      MD
      "project:plastic" => "## Relocated\n"
    )
  end

  def store_index
    {
      "global" => %w[24 1a2],            # NOTE: live unrelated global:24 impostor
      "project:plastic" => %w[11 13 19a 22c 75],
      "project:knowdb" => %w[1],
    }
  end

  def test_collapse_global_24_to_bare_22c_not_impostor
    nodes = { "11" => { sources: %w[global:24], chain: [] } }
    result = rebuild(nodes, relocation_map: relocation_map, store_index: store_index)
    assert_equal %w[22c], result[:nodes]["11"][:sources]
    c = result[:changes].find { |x| x[:kind] == :collapse }
    assert_equal "global:24", c[:before]
    assert_equal "22c", c[:after]
  end

  def test_collapse_global_14a_to_bare_19a_keep_other_source
    nodes = { "13" => { sources: %w[global:14a 75], chain: [] } }
    result = rebuild(nodes, relocation_map: relocation_map, store_index: store_index)
    assert_equal %w[19a 75], result[:nodes]["13"][:sources]
  end

  def test_healthy_cross_store_ref_unchanged
    nodes = { "1" => { sources: %w[global:1a2], chain: [] } }
    result = rebuild(nodes, store: "project:knowdb",
                            relocation_map: relocation_map, store_index: store_index)
    assert_equal %w[global:1a2], result[:nodes]["1"][:sources]
    refute(result[:changes].any? { |c| c[:kind] == :repoint || c[:kind] == :collapse })
  end

  def test_dead_cross_store_ref_dropped_and_logged
    nodes = { "11" => { sources: %w[global:999], chain: [] } }
    result = rebuild(nodes, relocation_map: relocation_map, store_index: store_index)
    assert_equal [], result[:nodes]["11"][:sources]
    assert(result[:changes].any? { |c| c[:kind] == :drop && c[:before] == "global:999" })
  end

  # --- idempotency (AC): second pass yields zero changes ---

  def test_idempotency_second_pass_zero_changes
    nodes = {
      "11" => { sources: %w[global:24], chain: [] },
      "13" => { sources: %w[global:14a 75 75], chain: %w[19a] }, # dup + I3 overlap
      "19a" => { sources: [], chain: [] },
      "22c" => { sources: [], chain: [] },
      "75" => { sources: [], chain: [] },
    }
    first = rebuild(nodes, relocation_map: relocation_map, store_index: store_index)
    refute_empty first[:changes]

    second = rebuild(first[:nodes], relocation_map: relocation_map, store_index: store_index)
    assert_empty second[:changes], "second pass must be a no-op (fixpoint)"
    assert_equal first[:nodes], second[:nodes]
  end
end
