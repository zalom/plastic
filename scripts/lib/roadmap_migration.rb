# encoding: UTF-8
# frozen_string_literal: true

require_relative "roadmap_graph"
require_relative "roadmap_render"
require_relative "roadmap_savepoint"
require_relative "graph_edges"
require_relative "graph_file"
require_relative "atomic_write"

# RoadmapMigration (intent 337, n4): reads a graphless roadmap's existing
# batch order and returns the conservative edge set that preserves it -
# every entry of batch N needs every entry of batch N-1, batch 1 needs
# nothing. Never overwrites a roadmap that already carries a "## Graph" (or
# graph-like, row 4.15) heading: the owner's hand-edited edges are the only
# place a cross-intent edge lives, and a derived guess must never replace
# them. Block splitting and entry-id extraction are the same surgical
# parser RoadmapRender uses (n3) - never a second one.
module RoadmapMigration
  module_function

  GRAPH_HEADING_RE = /\A##\s+Graph\b/.freeze

  # {ok:, skipped:, edges:, reason:}. Computes only; writes nothing.
  def derive(path, index_path: nil)
    text = File.read(path)

    if text.each_line.any? { |l| l.strip.match?(GRAPH_HEADING_RE) }
      return { ok: false, skipped: true, edges: {}, reason: "already carries a ## Graph (or graph-like) heading, left untouched" }
    end

    begin
      body = RoadmapSavepoint.grouping_section_body(text, path: path)
    rescue RoadmapSavepoint::MissingGroupingHeading => e
      return { ok: false, skipped: false, edges: {}, reason: e.message }
    end

    _preamble, blocks = RoadmapRender.split_into_blocks(body)
    batch_ids = blocks.map { |b| b[:lines].filter_map { |l| RoadmapRender.entry_id(l) } }

    entries_by_id = entry_statuses(text, path, index_path)

    edges = {}
    batch_ids.each_with_index do |ids, i|
      prev_ids = i.zero? ? [] : batch_ids[i - 1].reject { |id| abandoned?(entries_by_id, id) }
      # An id repeated across two batches (row 4.16) must never need itself:
      # exclude it from its own prev_ids before assigning.
      ids.each { |id| edges[id] = prev_ids.reject { |p| p == id } }
    end

    cyc = GraphEdges.cycle(edges)
    return { ok: false, skipped: false, edges: {}, reason: "derived graph is cyclic: #{cyc.join(' > ')}" } if cyc

    { ok: true, skipped: false, edges: edges, reason: nil }
  end

  # derive + render "## Graph" through AtomicWrite. A skip (row 4.3) or a
  # refusal (cyclic, row 4.5) writes nothing and reports why.
  def write(path, renamer: File.method(:rename), dry_run: false, index_path: nil)
    result = derive(path, index_path: index_path)
    return { ok: result[:ok], written: false, content: nil, skipped: result[:skipped], reason: result[:reason] } unless result[:ok]

    graph_text = render_edges(result[:edges])
    original = File.read(path)
    content = GraphFile.replace_or_append_section(original, "## Graph", graph_text)

    if dry_run
      { ok: true, written: false, content: content, skipped: false, reason: nil }
    else
      AtomicWrite.write(path, content, renamer: renamer)
      { ok: true, written: true, content: content, skipped: false, reason: nil }
    end
  end

  def render_edges(edges)
    lines = edges.map do |id, needs|
      "- #{id} needs #{needs.empty? ? 'nothing' : needs.join(' ')}\n"
    end
    lines.join
  end

  def entry_statuses(text, path, index_path)
    entries_by_id, = RoadmapGraph.parse_entries(text, path)
    resolved_index = index_path || RoadmapRender.default_index_path(path)
    index_map = RoadmapGraph.load_index(resolved_index)
    entries_by_id.each_value { |e| e[:status] = RoadmapGraph.reconcile_status(index_map[e[:id]], e[:raw_status]) }
    entries_by_id
  rescue RoadmapSavepoint::MissingGroupingHeading
    {}
  end

  def abandoned?(entries_by_id, id)
    entries_by_id[id] && entries_by_id[id][:status] == "abandoned"
  end
end
