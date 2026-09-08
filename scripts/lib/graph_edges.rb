# encoding: UTF-8
# frozen_string_literal: true

# GraphEdges (intent 334, n1): the shared `needs` syntax and cycle-path check
# (327 D2r-D4r, D12r). Parses a "## Graph" section's edge lines into a node
# set and an edge map, the one parser an intent's graph.md and a roadmap's
# own ## Graph section both use unchanged (C1, fold A5): the same list-item
# grammar, the same root keyword, the same cycle walk. Deliberately loose
# about what an id looks like - a roadmap id is numeric ("334", "340a"), a
# node id carries a kind prefix ("n1") - the kind-prefix rule belongs to
# NodeFile and WorkGraphValidator, never here (D12r, fold A6).
#
# Grammar (D2r/D3r): a list item shaped "- <id> needs <target> [<target>
# ...]", ending at end of line. The single literal target "nothing" declares
# a root and must be the ONLY target on the line. Any line that does not
# start with "- <token> needs" is prose and is skipped in silence. A line
# that DOES look like an edge is held to the grammar strictly: no target at
# all, "nothing" alongside other targets, or a target token carrying
# sentence punctuation (a period, a colon, ...) rather than the loose
# id-token charset, is an error naming the line, never a silently
# mis-parsed edge or an invented node (fold A7).
#
# Pure and side-effect-free; never raises across the boundary, matching the
# Result-hash convention every library in scripts/lib/ follows.
module GraphEdges
  module_function

  EDGE_LEAD_RE = /\A-\s*(\S+)\s+needs\b(.*)\z/.freeze
  TOKEN_RE = /\A[A-Za-z0-9][A-Za-z0-9_-]*\z/.freeze
  ROOT_TARGET = "nothing"

  # {nodes:, edges:, errors:} - nodes is the declared ids together with every
  # id any edge targets (fold A5), in first-seen order; edges maps a declared
  # id to its target ids (empty for a root); errors names each malformed
  # edge-shaped line. Prose lines contribute nothing and raise nothing.
  def parse(section_text)
    declared_order = []
    edges = {}
    targeted = []
    errors = []

    section_text.to_s.each_line do |raw_line|
      line = raw_line.chomp("\n").chomp("\r")
      stripped = line.strip
      next if stripped.empty?

      m = stripped.match(EDGE_LEAD_RE)
      next unless m

      id = m[1]
      raw_targets = m[2].to_s.strip.split(/\s+/)

      if raw_targets.empty?
        errors << "malformed edge line, no target: #{stripped.inspect}"
        next
      end

      if raw_targets.include?(ROOT_TARGET) && raw_targets.length > 1
        errors << "prose tail after targets: #{stripped.inspect}"
        next
      end

      bad_token = raw_targets.find { |t| t != ROOT_TARGET && !t.match?(TOKEN_RE) }
      if bad_token
        errors << "prose tail after targets: #{stripped.inspect}"
        next
      end

      if edges.key?(id)
        errors << "duplicate node declaration for #{id.inspect}: #{stripped.inspect}"
        next
      end

      targets = raw_targets == [ROOT_TARGET] ? [] : raw_targets
      declared_order << id
      edges[id] = targets
      targeted.concat(targets)
    end

    nodes = declared_order.dup
    targeted.each { |t| nodes << t unless nodes.include?(t) }

    { nodes: nodes, edges: edges, errors: errors }
  end

  # The cycle as a path with the entry id repeated (D4r), or nil when the
  # graph is acyclic. A node reachable by two distinct paths (a diamond) is
  # never mistaken for a cycle: once a node's whole subtree is walked clean
  # it is marked visited and never re-examined.
  def cycle(edges)
    visiting = {}
    visited = {}
    path = []

    edges.each_key do |node|
      next if visited[node]
      found = walk(node, edges, visiting, visited, path)
      return found if found
    end
    nil
  end

  def walk(node, edges, visiting, visited, path)
    if visiting[node]
      idx = path.index(node)
      return path[idx..] + [node]
    end
    return nil if visited[node]

    visiting[node] = true
    path.push(node)
    (edges[node] || []).each do |target|
      found = walk(target, edges, visiting, visited, path)
      return found if found
    end
    path.pop
    visiting.delete(node)
    visited[node] = true
    nil
  end
end
