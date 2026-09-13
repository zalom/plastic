# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_edges"
require_relative "ready_set"

# GraphTree (intent 337, n2, incorporates 327a): draws any edge map ({id => [needs...]})
# as an indented tree with box-drawing branches. A node may have any number
# of children; a node several branches need (fan-out) is drawn once, at the
# point where those branches join. A node that itself needs several things
# (fan-in) can only occupy one position in the tree: it hangs under its
# highest-batch need, ties broken by smallest id, with its other needs shown
# as converging references at the join (row 2.14, merged at the 2026-09-10
# plan review). Pure, plain text, no roadmap knowledge, so the same
# renderer serves the roadmap file, the roadmap screens, and later the node
# scope. Batch numbers (for placement) and the topological sort come from
# ReadySet - the ONE sort (327 D1) - never a second local one here.
module GraphTree
  module_function

  def render(edges:, labels:, marks:, width:)
    edges = edges || {}
    nodes = ReadySet.all_nodes(edges)

    cyc = GraphEdges.cycle(edges)
    if cyc
      return { ok: false, text: nil, error: "cyclic graph, cannot render a tree: #{cyc.join(' > ')}", cycle: cyc }
    end

    if nodes.empty?
      return { ok: true, text: "(no dependencies)\n", error: nil, cycle: nil }
    end

    batch_result = ReadySet.batches(edges)
    batch_of = {}
    batch_result[:batches].each_with_index { |layer, i| layer.each { |id| batch_of[id] = i + 1 } }

    primary_parent = {}
    converging = {}
    nodes.each do |id|
      needs = (edges[id] || []).uniq
      next if needs.empty?

      primary = needs.min_by { |n| [-(batch_of[n] || 0), n] }
      primary_parent[id] = primary
      others = needs - [primary]
      converging[id] = others.sort unless others.empty?
    end

    children_of = Hash.new { |h, k| h[k] = [] }
    primary_parent.each { |child, parent| children_of[parent] << child }
    children_of.each_value { |list| list.sort! { |a, b| [batch_of[a] || 0, a] <=> [batch_of[b] || 0, b] } }

    roots = nodes.select { |id| (edges[id] || []).empty? }.sort

    labels ||= {}
    marks ||= {}
    critical = (marks[:critical_path] || []).to_a
    ready = (marks[:ready] || []).to_a

    lines = []
    roots.each { |id| append_node(id, "", "", lines, children_of, labels, critical, ready, converging, width) }

    { ok: true, text: "#{lines.join("\n")}\n", error: nil, cycle: nil }
  end

  # `ancestor_prefix` is the continuation string every ancestor above this
  # node contributes ("│   " when that ancestor still has a later sibling
  # to draw, "    " when it was the last child); `connector` is this node's
  # own branch glyph off its parent ("├── " / "└── "), empty for a root.
  def append_node(id, ancestor_prefix, connector, lines, children_of, labels, critical, ready, converging, width)
    lines << render_line(ancestor_prefix + connector, id, labels, critical, ready, converging, width)

    continuation = connector == "└── " ? "    " : (connector.empty? ? "" : "│   ")
    child_ancestor_prefix = ancestor_prefix + continuation

    children = children_of[id] || []
    children.each_with_index do |child_id, i|
      last = i == children.length - 1
      child_connector = last ? "└── " : "├── "
      append_node(child_id, child_ancestor_prefix, child_connector, lines, children_of, labels, critical, ready, converging, width)
    end
  end

  def render_line(connector, id, labels, critical, ready, converging, width)
    label = labels.fetch(id, id).to_s
    text = critical.include?(id) ? "* #{label}" : label
    text += " (also needs #{converging[id].join(', ')})" if converging[id]
    text += " (ready)" if ready.include?(id)

    available = width - connector.length
    if available.positive? && text.length > available
      text = available > 3 ? "#{text[0, available - 3]}..." : text[0, available]
    end

    "#{connector}#{text}"
  end
end
