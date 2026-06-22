# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../scripts/lib/links_projection"

# ACTION 1 — pure LinksProjection tests. Hermetic: the resolver is an in-memory
# Hash lookup, no file IO, no eval, no ENV. Pins the canonical I5 entry shape,
# the mandatory sources-first ordering, the cross-store form, the empty-state, and
# the resolver-miss-fails-loud contract.
class LinksProjectionTest < Minitest::Test
  # An in-memory resolver: maps ref -> { target:, label: }. A missing key returns
  # nil, which must make the projection raise UnresolvedRef.
  MAP = {
    "40" => { target: "40--store-graph", label: "Build the store graph" },
    "60" => { target: "60--bypass-create", label: "Block the create bypass" },
    "72" => { target: "72--links-graph-projection", label: "Project links" },
    "knowdb:1" => { target: "knowdb:1--knowdb-app", label: "Build the knowdb app" },
  }.freeze

  def resolver
    ->(ref) { MAP[ref] }
  end

  def test_pinned_entry_shape_for_source_and_chain
    text = LinksProjection.section(sources: ["40"], chain: ["60"], resolve: resolver)
    assert_equal(
      "## Links\n" \
      "- [[40--store-graph|Build the store graph]]\n" \
      "- [[60--bypass-create|Block the create bypass]]\n",
      text
    )
  end

  def test_sources_first_ordering
    # sources:["40"], chain:["60"] — the source line must precede the chain line.
    text = LinksProjection.section(sources: ["40"], chain: ["60"], resolve: resolver)
    src_idx = text.index("40--store-graph")
    chain_idx = text.index("60--bypass-create")
    refute_nil src_idx
    refute_nil chain_idx
    assert src_idx < chain_idx, "a source entry must precede a chain entry"
  end

  # Load-bearing: this test FAILS if the projection ever emits a chain entry before
  # a source entry. Multiple sources + multiple chain; every source index must be
  # less than every chain index.
  def test_no_chain_entry_ever_precedes_a_source_entry
    text = LinksProjection.section(sources: %w[40 60], chain: %w[72], resolve: resolver)
    source_targets = %w[40--store-graph 60--bypass-create]
    chain_targets = %w[72--links-graph-projection]
    max_source = source_targets.map { |t| text.index(t) }.max
    min_chain = chain_targets.map { |t| text.index(t) }.min
    assert max_source < min_chain,
           "every source entry must come before every chain entry (sources-first)"
  end

  def test_within_group_frontmatter_order_preserved
    text = LinksProjection.section(sources: %w[60 40], chain: [], resolve: resolver)
    assert text.index("60--bypass-create") < text.index("40--store-graph"),
           "frontmatter order is preserved within the sources group"
  end

  def test_cross_store_entry_shape
    text = LinksProjection.section(sources: [], chain: ["knowdb:1"], resolve: resolver)
    assert_equal(
      "## Links\n- [[knowdb:1--knowdb-app|Build the knowdb app]]\n",
      text
    )
  end

  def test_empty_state
    text = LinksProjection.section(sources: [], chain: [], resolve: resolver)
    assert_equal(
      "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      text
    )
  end

  def test_resolver_miss_raises_unresolved_ref
    err = assert_raises(LinksProjection::UnresolvedRef) do
      LinksProjection.section(sources: ["does-not-exist"], chain: [], resolve: resolver)
    end
    assert_equal "does-not-exist", err.ref
  end

  def test_resolver_returning_blank_target_raises
    blank = ->(_ref) { { target: "  ", label: "x" } }
    assert_raises(LinksProjection::UnresolvedRef) do
      LinksProjection.section(sources: ["40"], chain: [], resolve: blank)
    end
  end

  # Defensive: a ref appearing in both groups is projected once, in sources only.
  def test_overlap_projected_in_sources_only
    text = LinksProjection.section(sources: ["40"], chain: ["40"], resolve: resolver)
    assert_equal 1, text.scan("40--store-graph").size
  end
end
