# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_file"
require_relative "graph_edges"
require_relative "ready_set"
require_relative "roadmap_savepoint"

# RoadmapGraph (intent 337, n1): reads one roadmap file into the same shape
# the node scope already uses - entries with their INDEX-reconciled status,
# the edge map from "## Graph", the cycle path when one exists, the
# topological batches, the critical paths, and the ready set. Edges are
# parsed by GraphEdges; batches, critical paths, and downstream hops come
# from ReadySet (327 D1, C1: the one parser, the one topological sort - a
# local copy of either here is exactly the drift 327 forbids). This module
# writes no file and reads no clock or environment variable (row 1.14);
# every fact is either a value passed in or read once from the two paths
# `analyze` is given.
module RoadmapGraph
  module_function

  ENTRY = /\A-\s*\[([ xX])\]\s+(\S+)\s+(.*?)[—-]\s*(queued|delivering|delivered|abandoned|blocked)\b/.freeze
  WAVE_HEADING = /\A###\s+(.+?)\s*\z/.freeze

  INDEX_TAGS = { "Completed" => "delivered", "Abandoned" => "abandoned", "Active" => :active, "Future" => "queued" }.freeze

  # analyze(roadmap_path, index_path:) -> a Result hash. Never raises across
  # the boundary: a missing ## Graph section, a missing grouping heading, a
  # cyclic graph, or an invalid byte in either file all become a named
  # `reason` or an empty result, never an exception (rows 1.8, 1.9, 1.13).
  def analyze(roadmap_path, index_path: nil)
    text = read_utf8(roadmap_path)

    graph_section = GraphFile.section_body(text, "## Graph")
    unless graph_section
      return result(has_graph: false, reason: "no ## Graph section in #{roadmap_path}")
    end

    parsed_edges = GraphEdges.parse(GraphFile.strip_fenced_blocks(graph_section))

    entries_by_id, order = begin
      parse_entries(text, roadmap_path)
    rescue RoadmapSavepoint::MissingGroupingHeading => e
      return result(has_graph: true, reason: e.message)
    end

    index_map = load_index(index_path)
    entries_by_id.each_value { |e| e[:status] = reconcile_status(index_map[e[:id]], e[:raw_status]) }

    declared_and_targeted = parsed_edges[:nodes]
    entry_ids = order.dup

    # 1.6: an entry the graph never named (not declared, not targeted) is
    # included as a root, so a partly migrated roadmap never silently
    # drops real work from the batches.
    edges = parsed_edges[:edges].dup
    entry_ids.each do |id|
      next if declared_and_targeted.include?(id)

      edges[id] = []
      entries_by_id[id][:in_graph] = false
    end
    entry_ids.each do |id|
      entries_by_id[id][:in_graph] = true if declared_and_targeted.include?(id) && entries_by_id[id][:in_graph].nil?
    end

    # 1.7: a graph id with no batch entry is named in `dangling`, never
    # invented as a fake entry with no title.
    dangling = declared_and_targeted.reject { |id| entries_by_id.key?(id) }

    cyc = GraphEdges.cycle(edges)
    if cyc
      return result(has_graph: true, entries: entries_by_id, edges: edges, dangling: dangling,
                     cycle: cyc, errors: parsed_edges[:errors])
    end

    batch_result = ReadySet.batches(edges)
    batches = batch_result[:ok] ? order_batches(batch_result[:batches], order) : []
    path_result = ReadySet.critical_paths(edges)

    status_map = entries_by_id.each_with_object({}) { |(id, e), h| h[id] = e[:status] }
    dead_ends = entry_ids.select do |id|
      entries_by_id[id][:status] != "delivered" && ReadySet.dead_end?(id, edges, status_map)
    end

    ready = entry_ids.select do |id|
      entries_by_id[id][:status] == "queued" &&
        (edges[id] || []).all? { |t| status_map[t] == "delivered" }
    end

    result(
      has_graph: true,
      entries: entries_by_id,
      edges: edges,
      dangling: dangling,
      cycle: nil,
      batches: batches,
      batches_error: batch_result[:ok] ? nil : batch_result[:error],
      critical_paths: path_result[:ok] ? path_result : nil,
      dead_ends: dead_ends,
      ready: ready,
      errors: parsed_edges[:errors]
    )
  end

  # --- shared building blocks other callers (RoadmapQueue, n9) reuse --------

  # The one place that knows how a roadmap's own "## Graph" section is read:
  # an exact heading (GraphFile), fenced examples stripped, and an edgeless
  # section treated the same as no section at all. Returns GraphEdges.parse's
  # own Result hash, or nil.
  def parse_graph_section(text)
    section = GraphFile.section_body(text, "## Graph")
    return nil if section.nil?

    parsed = GraphEdges.parse(GraphFile.strip_fenced_blocks(section))
    return nil if parsed[:nodes].empty?

    parsed
  end

  # ReadySet.batches's own topological layers (the one sort, D1), reordered
  # WITHIN each layer to match `order` - typically the roadmap file's own
  # entry-encounter order (row 1.16/9.8). A computed batch names which layer
  # an id is in; it must never silently become a ranking decision by
  # defaulting to a lexical sort of ids that happen to share a layer.
  def order_batches(batches, order)
    rank = {}
    order.each_with_index { |id, i| rank[id] = i }
    batches.map { |layer| layer.sort_by { |id| [rank[id] || order.length, id] } }
  end

  # --- entries -----------------------------------------------------------------

  def parse_entries(text, roadmap_path)
    body = RoadmapSavepoint.grouping_section_body(text, path: roadmap_path)
    entries = {}
    order = []
    body.each_line do |line|
      stripped = line.chomp.strip
      m = stripped.match(ENTRY)
      next unless m

      id = m[2]
      next if entries.key?(id)

      entries[id] = { id: id, title: m[3].strip, raw_status: m[4].downcase, in_graph: nil }
      order << id
    end
    [entries, order]
  end

  def reconcile_status(tag, raw_status)
    case tag
    when "delivered" then "delivered"
    when "abandoned" then "abandoned"
    when "queued" then "queued"
    when :active then raw_status == "delivered" ? "delivering" : raw_status
    else raw_status
    end
  end

  def load_index(index_path)
    map = {}
    return map unless index_path && File.exist?(index_path)

    text = read_utf8(index_path)
    INDEX_TAGS.each do |heading, tag|
      section_body(text, heading).each_line do |line|
        stripped = line.strip
        next unless stripped.start_with?("- [")

        m = stripped.match(/\A-\s*\[(\S+)\s/)
        map[m[1]] = tag if m
      end
    end
    map
  end

  def section_body(text, heading)
    m = text.match(/^##\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^##\s|\z)/m)
    m ? m[1] : ""
  end

  # 1.13: an invalid byte in either file is scrubbed, never raised across
  # the boundary.
  def read_utf8(path)
    text = File.read(path)
    text.force_encoding(Encoding::UTF_8)
    text.valid_encoding? ? text : text.scrub("")
  end

  def result(has_graph:, reason: nil, entries: {}, edges: {}, dangling: [], cycle: nil,
             batches: [], batches_error: nil, critical_paths: nil, dead_ends: [], ready: [], errors: [])
    {
      has_graph: has_graph,
      reason: reason,
      entries: entries,
      edges: edges,
      dangling: dangling,
      cycle: cycle,
      batches: batches,
      batches_error: batches_error,
      critical_paths: critical_paths,
      dead_ends: dead_ends,
      ready: ready,
      errors: errors,
    }
  end
end
