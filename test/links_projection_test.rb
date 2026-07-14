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

  # Finding 2 (independent review of intent 189): a :dead resolver miss and an
  # :unknown_store resolver miss used to share one generic UnresolvedRef message.
  # They must now be distinguishable, so project-links' FAILED audit lines can tell
  # "genuinely dead" apart from "store not discovered this run, left untouched".
  def test_dead_and_unknown_store_reasons_produce_different_messages
    dead_resolver = ->(_ref) { { reason: :dead } }
    unknown_resolver = ->(_ref) { { reason: :unknown_store, store: "ghost" } }

    dead_err = assert_raises(LinksProjection::UnresolvedRef) do
      LinksProjection.section(sources: ["x"], chain: [], resolve: dead_resolver)
    end
    unknown_err = assert_raises(LinksProjection::UnresolvedRef) do
      LinksProjection.section(sources: ["x"], chain: [], resolve: unknown_resolver)
    end

    assert_equal :dead, dead_err.reason
    assert_equal :unknown_store, unknown_err.reason
    refute_equal dead_err.message, unknown_err.message
    assert_match(/dead/, dead_err.message)
    assert_match(/unknown store/, unknown_err.message)
    assert_includes unknown_err.message, "ghost"
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

  # REGRESSION (intent 72): dedup must be by RESOLVED target, not the raw ref
  # string. The same intent referenced as a bare id in sources AND as `store:id` in
  # chain (e.g. via a relocation) resolves to the SAME target and must render once.
  def test_dedup_by_resolved_target_not_raw_ref
    aliased = ->(ref) do
      case ref
      when "40", "plastic:40"
        { target: "40--store-graph", label: "Build the store graph" }
      end
    end
    text = LinksProjection.section(sources: ["40"], chain: ["plastic:40"], resolve: aliased)
    assert_equal 1, text.scan("40--store-graph").size,
                 "the same resolved target must render exactly once"
    # Sources win: it appears once, with no duplicate chain entry.
    assert_equal "## Links\n- [[40--store-graph|Build the store graph]]\n", text
  end

  # --- ACTION_1 (intent 192): parse_entries / render_entries ---

  def test_parse_entries_extracts_target_and_label_in_order
    text = "## Links\n- [[10--a|A intent]]\n- [[knowdb:1--b|B intent]]\n"
    assert_equal(
      [{ target: "10--a", label: "A intent" }, { target: "knowdb:1--b", label: "B intent" }],
      LinksProjection.parse_entries(text)
    )
  end

  def test_parse_entries_ignores_heading_and_empty_state_comment
    assert_equal [], LinksProjection.parse_entries(LinksProjection.empty_section)
  end

  def test_parse_entries_ignores_non_entry_lines
    assert_equal [], LinksProjection.parse_entries("## Links\nsome stray prose\n")
  end

  def test_render_entries_falls_back_to_empty_section_when_given_nothing
    assert_equal LinksProjection.empty_section, LinksProjection.render_entries([])
    assert_equal LinksProjection.empty_section, LinksProjection.render_entries(nil)
  end

  def test_render_entries_matches_entry_line_shape
    text = LinksProjection.render_entries([{ target: "10--a", label: "A intent" }])
    assert_equal "## Links\n- [[10--a|A intent]]\n", text
  end

  # Round-trip: parsing #section's own output and re-rendering it must reproduce
  # the identical text (this is what lets project-links safely merge preserved
  # orphan entries onto a freshly-computed canonical section).
  def test_parse_then_render_entries_round_trips_section_output
    text = LinksProjection.section(sources: %w[40 60], chain: ["knowdb:1"], resolve: resolver)
    round_tripped = LinksProjection.render_entries(LinksProjection.parse_entries(text))
    assert_equal text, round_tripped
  end
end
