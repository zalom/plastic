# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_rebuild"
require_relative "frontmatter_writer"

# RestoreIntentV1 - pure graph math for restoring a completed intent's frontmatter
# graph across a v1 prose revert (intent 193). No file IO, no git, no `system`.
#
# The rule this module carries: prose reverts to v1; the sources/chain graph is
# APPEND-ONLY and is the UNION of the v1 snapshot and the current snapshot, never
# a re-derivation from other intents' reciprocal edges (that would silently erase
# legitimate I2-asymmetry edges doctor.rb never auto-fixes). Before the union is
# written, every edge (from either snapshot) is target-resolved by reusing
# GraphRebuild.resolve_ref verbatim, the same classifier rebuild-graph and
# doctor.rb already share: a :dead edge (resolves to no id in any known store) is
# dropped and reported; :same_store, :cross_store, and :unknown_store edges are
# all kept (bias toward preserving an edge that might be real; only positive proof
# of non-existence justifies a drop).
module RestoreIntentV1
  module_function

  # PURE. Computes the desired sources/chain for a restore.
  #
  # Returns:
  #   { sources: [...], chain: [...],
  #     dropped:      [ { field: :sources|:chain, ref: "<id or store:id>" }, ... ],
  #     unverified:   [ { field: :sources|:chain, ref: "<id or store:id>" }, ... ],
  #     current_only: [ { field: :sources|:chain, ref: "<id or store:id>" }, ... ] }
  #
  # `current_only` names every edge present in the CURRENT snapshot but absent from
  # the v1 snapshot (D3 transparency): an edge added by the very change being
  # reverted, which the union now carries forward. Named explicitly regardless of
  # its target-resolution outcome, so it is never a silent side effect.
  def compute_graph(v1_sources:, v1_chain:, current_sources:, current_chain:,
                     referer_store:, relocation_map:, store_index:)
    sources_result = resolve_union(v1_sources, current_sources, :sources,
                                    referer_store, relocation_map, store_index)
    chain_result = resolve_union(v1_chain, current_chain, :chain,
                                  referer_store, relocation_map, store_index)

    {
      sources: sources_result[:kept],
      chain: chain_result[:kept],
      dropped: sources_result[:dropped] + chain_result[:dropped],
      unverified: sources_result[:unverified] + chain_result[:unverified],
      current_only: current_only_edges(v1_sources, current_sources, :sources) +
                    current_only_edges(v1_chain, current_chain, :chain),
    }
  end

  # PURE. Union two edge arrays (deduped, order-preserving, first array's order
  # wins for shared entries), then target-resolve each via GraphRebuild.resolve_ref.
  def resolve_union(v1_edges, current_edges, field, referer_store, relocation_map, store_index)
    union = (Array(v1_edges).map(&:to_s) + Array(current_edges).map(&:to_s)).uniq
    kept = []
    dropped = []
    unverified = []

    union.each do |ref|
      classification = GraphRebuild.resolve_ref(
        ref, referer_store: referer_store, relocation_map: relocation_map, store_index: store_index
      )
      case classification[:status]
      when :dead
        dropped << { field: field, ref: ref }
      when :unknown_store
        kept << ref
        unverified << { field: field, ref: ref }
      else # :same_store, :cross_store
        kept << ref
      end
    end

    { kept: kept, dropped: dropped, unverified: unverified }
  end

  # PURE. Every edge present in `current_edges` but absent from `v1_edges`
  # (raw, before target resolution): the set the restore is about to carry
  # forward that v1 itself never had.
  def current_only_edges(v1_edges, current_edges, field)
    v1_set = Array(v1_edges).map(&:to_s)
    Array(current_edges).map(&:to_s).uniq.reject { |ref| v1_set.include?(ref) }
                         .map { |ref| { field: field, ref: ref } }
  end

  # PURE. Reapply the computed graph onto v1's exact prose. Delegates entirely to
  # FrontmatterWriter; this module never rewrites YAML itself.
  def apply_graph(v1_content, desired_sources:, desired_chain:)
    FrontmatterWriter.rewrite_arrays(v1_content, sources: desired_sources, chain: desired_chain)
  end

  # PURE. Render one revisions.md entry (intent 107's append-only, move-and-record
  # convention). `n` is the next revision number for this intent's revisions.md.
  # `files` names every file reverted to its v1 content in this restore.
  def render_revision_entry(n, at:, timestamp:, files:, before_sources:, after_sources:,
                             before_chain:, after_chain:, dropped:)
    lines = []
    lines << "## Revision v#{n} - #{timestamp}"
    lines << "- Why: restore-to-v1 preserved the frontmatter graph across a completed-intent " \
             "restore [rule: restored-to-v1]"
    lines << "- Prior location: frontmatter - sources/chain; prose reverted to ref #{at}"
    lines << "- Files reverted to v1: #{files.empty? ? "(none, already at v1)" : files.join(", ")}"
    lines << "- Change: sources (before: #{before_sources.inspect} -> after: #{after_sources.inspect}); " \
             "chain (before: #{before_chain.inspect} -> after: #{after_chain.inspect})"
    unless dropped.empty?
      lines << ""
      dropped.each do |d|
        lines << "  Dropped dead edge in #{d[:field]} -> #{d[:ref]}: target intent does not exist."
      end
    end
    "#{lines.join("\n")}\n"
  end

  # PURE. Render the dry-run/apply human-readable report. `v1` and `current` are
  # { sources:, chain: } snapshots shown alongside the resulting union so a
  # reviewer can see all three shapes without recomputing anything by hand (spec
  # acceptance criterion: dry-run prints the v1 graph, the current graph, and the
  # resulting union, not only the union).
  def render_report(base:, at:, prose_changes:, v1:, current:, graph:, apply:)
    lines = []
    lines << "restore-intent-v1: #{base} at #{at} (#{apply ? "APPLY" : "DRY RUN"})"
    prose_changes.each { |f| lines << "  prose: revert #{f}" }
    lines << "  v1 sources -> #{v1[:sources].inspect}"
    lines << "  v1 chain -> #{v1[:chain].inspect}"
    lines << "  current sources -> #{current[:sources].inspect}"
    lines << "  current chain -> #{current[:chain].inspect}"
    lines << "  union sources -> #{graph[:sources].inspect}"
    lines << "  union chain -> #{graph[:chain].inspect}"
    graph[:dropped].each do |d|
      lines << "  DROPPED dead edge (#{d[:field]}): #{d[:ref]} - target intent does not exist"
    end
    graph[:unverified].each do |d|
      lines << "  UNVERIFIED edge (#{d[:field]}): #{d[:ref]} - store unknown, kept"
    end
    graph[:current_only].each do |d|
      lines << "  CURRENT-ONLY edge (#{d[:field]}): #{d[:ref]} - added by the change being " \
               "reverted, now surviving the restore"
    end
    lines.join("\n")
  end
end
