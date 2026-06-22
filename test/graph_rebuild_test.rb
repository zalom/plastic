# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/graph_rebuild"

# ACTION 1 — pure relocation-map + cross-store-resolver tests. Hermetic: every
# input is an injected string or in-memory map. No file IO, no eval, no ENV.
class GraphRebuildResolverTest < Minitest::Test
  # Real global Relocated log shape: `store:id → project:id`, multi-pair lines,
  # plus a single-pair line with trailing parenthetical prose.
  GLOBAL_INDEX = <<~MD
    # Plastic Intent Index

    ## Completed

    ## Relocated
    Plastic project intents relocated on 2026-06-08:
    - global:12 → project:17, global:13 → project:18, global:14 → project:19
    - global:14a → project:19a, global:24 → project:22c
    - global:22 → project:75 (abandoned, superseded by project:13 plastic:doctor)

    ## Future
  MD

  # Real plastic Relocated log shape: backtick-wrapped bare ids, same-store moves,
  # trailing prose. Includes a multi-hop chain a → b → c (`9x → 9y`, `9y → 9z`).
  PLASTIC_INDEX = <<~MD
    # Plastic Intent Index

    ## Relocated
    Re-rooted on 2026-06-16 (intent 40): provenance moved.
    - `1b1a1 → 41` (data & search layer)
    - `1b1a1a → 42` (MCP server)
    - `9x → 9y` (first hop)
    - `9y → 9z` (second hop)

    ## Completed
  MD

  def relocation_map
    GraphRebuild.build_relocation_map(
      "global" => GLOBAL_INDEX,
      "project:plastic" => PLASTIC_INDEX
    )
  end

  # store_index models live stores. NOTE the id-reuse hazard: a NEW unrelated
  # `global:24` (visual-ui-layer) exists in the global store, AND `22c` exists in
  # plastic. Direct resolution would accept the impostor; relocation must win.
  def store_index
    {
      "global" => %w[12 13 14 14a 22 24 1a2],
      "project:plastic" => %w[11 13 17 18 19 19a 22c 41 42 75 9z],
      "project:knowdb" => %w[1],
    }
  end

  def resolve(ref, referer)
    GraphRebuild.resolve_ref(
      ref,
      referer_store: referer,
      relocation_map: relocation_map,
      store_index: store_index
    )
  end

  def test_build_relocation_map_single_hop_store_prefixed
    map = relocation_map
    assert_equal ["project", "19a"], map[["global", "14a"]]
    assert_equal ["project", "22c"], map[["global", "24"]]
  end

  def test_build_relocation_map_parses_backtick_bare_ids_as_same_store
    map = relocation_map
    assert_equal ["project:plastic", "41"], map[["project:plastic", "1b1a1"]]
  end

  def test_build_relocation_map_multi_hop_collapses_to_final
    map = relocation_map
    # 9x → 9y → 9z must collapse to 9z
    assert_equal ["project:plastic", "9z"], map[["project:plastic", "9x"]]
  end

  def test_build_relocation_map_strips_trailing_prose
    map = relocation_map
    assert_equal ["project", "75"], map[["global", "22"]]
  end

  # NAMED HAZARD (AC id-reuse regression): relocation consulted BEFORE direct id
  # resolution. From a plastic intent, `global:24` must resolve to bare `22c`
  # (same store) — NOT the live unrelated `global:24`.
  def test_id_reuse_hazard_relocation_wins_over_coincidental_global_24
    result = resolve("global:24", "project:plastic")
    assert_equal :same_store, result[:status]
    assert_equal "22c", result[:id]
    refute_equal "global:24", result[:ref]
  end

  # NAMED HAZARD: global:14a → 19a, collapsed to bare same-store id for plastic.
  def test_global_14a_repoints_to_bare_19a
    result = resolve("global:14a", "project:plastic")
    assert_equal :same_store, result[:status]
    assert_equal "19a", result[:id]
  end

  def test_live_non_relocated_cross_store_ref_resolves_directly
    # knowdb:1.sources = ["global:1a2"] — live, different store, healthy.
    result = resolve("global:1a2", "project:knowdb")
    assert_equal :cross_store, result[:status]
    assert_equal "global:1a2", result[:ref]
  end

  def test_healthy_cross_store_chain_ref_kept
    # global:1a2.chain = ["knowdb:1"] — live, different store, healthy.
    result = resolve("knowdb:1", "global")
    assert_equal :cross_store, result[:status]
    assert_equal "knowdb:1", result[:ref]
  end

  def test_dead_ref_resolves_nowhere
    # No relocation, not in any store.
    result = resolve("global:999", "project:plastic")
    assert_equal :dead, result[:status]
    assert_equal "global:999", result[:ref]
  end

  def test_same_store_bare_ref_collapses_when_present
    result = resolve("19a", "project:plastic")
    assert_equal :same_store, result[:status]
    assert_equal "19a", result[:id]
  end

  def test_same_store_bare_ref_dead_when_absent
    result = resolve("does-not-exist", "project:plastic")
    assert_equal :dead, result[:status]
  end

  def test_empty_index_texts_yields_empty_map
    assert_equal({}, GraphRebuild.build_relocation_map({}))
    assert_equal({}, GraphRebuild.build_relocation_map(nil))
  end
end
