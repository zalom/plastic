# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_file"
require_relative "graph_edges"
require_relative "node_file"

# WorkGraphValidator (intent 334, n4): the in-batch reader over one intent's
# graph.md and nodes/ - 327's rule for budget, files, and the decision and
# research kinds (fold A17). {ok:, missing:, errors:}, the same Result shape
# ProjectValidator returns (fold B7). Named apart from
# IntentValidator#validate_graph, which already exists for the KNOWLEDGE
# graph and stays unrelated to this one under D40 (fold B9).
#
# Built over GraphFile, GraphEdges, and NodeFile only - never IntentValidator,
# never ReportScreen. Every check accumulates into `errors` rather than
# short-circuiting on the first one (fold: "the owner fixes one thing per
# run").
module WorkGraphValidator
  module_function

  def validate(intent_dir)
    missing = []
    errors = []

    graph_path = File.join(intent_dir, "graph.md")
    parsed = GraphFile.parse(graph_path)
    errors.concat(parsed[:errors])

    graph = parsed[:graph]
    if graph.nil?
      missing << "graph.md ## Graph section"
      return { ok: false, missing: missing, errors: errors }
    end

    nodes = graph[:nodes]
    edges = graph[:edges]
    declared_ids = edges.keys

    # Intent-scope dangling check: every node must be declared with its own
    # needs-line here (unlike a roadmap, which may have undeclared roots -
    # that reconciliation is G4's, not this validator's).
    (nodes - declared_ids).each { |id| errors << "needs target #{id.inspect} names no declared node" }

    cyc = GraphEdges.cycle(edges)
    errors << "cyclic graph, cannot validate: #{cyc.join(' > ')}" if cyc

    node_paths = Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort
    parsed_nodes = {}
    paths_by_id = Hash.new { |h, k| h[k] = [] }

    node_paths.each do |path|
      nf = NodeFile.parse(path)
      nf[:errors].each { |e| errors << "#{File.basename(path)}: #{e}" }
      id = nf[:node]
      next unless id

      paths_by_id[id] << path
      parsed_nodes[id] ||= nf
    end

    paths_by_id.each do |id, paths|
      next unless paths.length > 1

      errors << "node id #{id.inspect} claimed by more than one file: #{paths.map { |p| File.basename(p) }.join(', ')}"
    end

    declared_ids.each do |id|
      missing << "nodes/ file for #{id}" unless parsed_nodes.key?(id)
      errors << "declared node #{id.inspect} has no node file under nodes/" unless parsed_nodes.key?(id)
    end
    parsed_nodes.each_key do |id|
      errors << "node file for #{id.inspect} exists but ## Graph declares no such node" unless declared_ids.include?(id)
    end

    work_nodes = []
    verify_nodes = []

    declared_ids.each do |id|
      nf = parsed_nodes[id]
      next unless nf

      case nf[:kind]
      when "verify"
        verify_nodes << id
        errors << "verify node #{id.inspect} has no ## Criteria" unless has_section?(nf[:body], "## Criteria")
      when "decision"
        errors << "decision node #{id.inspect} has no ## Question with a question" unless has_nonblank_section?(nf[:body], "## Question")
      when "research"
        errors << "research node #{id.inspect} has no ## Deposit" unless has_section?(nf[:body], "## Deposit")
      when "work"
        work_nodes << id
        errors << "work node #{id.inspect} has no ## Steps" unless has_section?(nf[:body], "## Steps")
        errors << "work node #{id.inspect} has no ## Proven by" unless has_section?(nf[:body], "## Proven by")
      end
    end

    above_trivial_bar = work_nodes.length >= 2
    if above_trivial_bar
      verify_directive = parsed[:verify]
      directive_ok = verify_directive && !verify_directive[:reason].to_s.empty?

      unless directive_ok
        attached = verify_nodes.select { |vid| node_touches_graph?(vid, edges) }
        if attached.empty?
          errors << "two or more work nodes require a verify node attached to the graph, or a verify: none reason=<text> directive"
        end
      end

      work_nodes.each do |id|
        nf = parsed_nodes[id]
        next unless nf

        errors << "work node #{id.inspect} has no failure-mode matrix under a heading carrying its id" unless has_valid_matrix?(id, nf[:body])
      end
    end

    verify_nodes.each do |id|
      next if node_touches_graph?(id, edges)

      errors << "verify node #{id.inspect} exists but no edge reaches it (attach it or drop it)"
    end

    { ok: errors.empty?, missing: missing, errors: errors }
  end

  # A node "touches" the graph when some edge involves it on either side:
  # it targets something, or something targets it. A verify node declared
  # with "needs nothing" and targeted by nothing is fully isolated (fold
  # A13).
  def node_touches_graph?(id, edges)
    (edges[id] || []).any? || edges.values.any? { |targets| targets.include?(id) }
  end

  def has_section?(body, heading_text)
    NodeFile.split_by_headings(body.to_s).any? { |heading, _| heading.strip == heading_text }
  end

  def has_nonblank_section?(body, heading_text)
    NodeFile.split_by_headings(body.to_s).any? { |heading, section| heading.strip == heading_text && !section.strip.empty? }
  end

  def heading_tokens(heading)
    heading.to_s.sub(/\A#+\s*/, "").split(/[^A-Za-z0-9]+/)
  end

  # The matrix table must sit under a heading whose tokens include the
  # node's own id, and that heading must own at least one data row (fold
  # A1 - the same table-owning rule report_screen's resolver uses, so a
  # node's own Proven-by cell is never "not recorded" the moment it ships).
  def has_valid_matrix?(id, body)
    NodeFile.split_by_headings(body.to_s).any? do |heading, section|
      heading_tokens(heading).include?(id) && NodeFile.table_rows(section).any?
    end
  end
end
