# encoding: UTF-8
# frozen_string_literal: true

require_relative "graph_file"
require_relative "node_file"
require_relative "node_ledger"

# OutcomeReport (intent 339, G6): the report model over graph.md, nodes/, and
# the node ledger (n1), the generator and its command (n2), the plan-versus-
# delivered diff and the transitive stale walk (n3), and findings, read and
# capped (n4). Every rendered cell traces to graph.md, a node file, or a
# ledger line; an absent source renders as a named reason, never a guess
# (spec D1). Pure: no clock, no environment, every path an explicit argument.
# Edges come from GraphFile/GraphEdges only - never the older node-ledger
# reader intent 336 deletes in this same batch (spec D16).
module OutcomeReport
  module_function

  # One past NodeFile::KIND_PREFIX ("n" => "work", ...), so a declared node
  # with no node file on disk (matrix 1.8) still gets a kind, inferred from
  # its id's own prefix rather than left nil.
  KIND_BY_PREFIX = NodeFile::KIND_PREFIX.invert.freeze

  TITLE_LINE_RE = /\A#\s+\S+\s*-\s*(.+)\z/.freeze

  # {ok:, errors:, goal:, edges:, nodes:}. `edges` maps a declared node id to
  # the ids it needs (GraphEdges' own shape). `nodes` maps every id this
  # intent has ever mentioned - declared in graph.md, filed under nodes/, or
  # named in the ledger - to {declared:, file_present:, kind:, title:, state:,
  # fields:, retries:}. Never raises across its boundary (matrix 1.1, 1.6).
  def model(intent_dir)
    graph_path = File.join(intent_dir, "graph.md")
    unless File.exist?(graph_path)
      return { ok: false, errors: ["no graph.md at #{graph_path}"], goal: nil, edges: {}, nodes: {} }
    end

    parsed = GraphFile.parse(graph_path)
    edges = (parsed[:graph] && parsed[:graph][:edges]) || {}
    declared_ids = (parsed[:graph] && parsed[:graph][:nodes]) || []

    ledger_path = File.join(intent_dir, "savepoint.md")
    entries = NodeLedger.entries(ledger_path)
    ledger_ids = entries.map { |e| e[:subject] }.uniq
    file_ids = node_file_ids(intent_dir)

    all_ids = (declared_ids + ledger_ids + file_ids).uniq
    nodes = all_ids.each_with_object({}) do |id, memo|
      memo[id] = node_entry(intent_dir, id, declared_ids, entries)
    end

    { ok: parsed[:ok], errors: parsed[:errors] || [], goal: parsed[:goal], edges: edges, nodes: nodes }
  rescue StandardError => e
    { ok: false, errors: ["outcome report model crashed: #{e.message}"], goal: nil, edges: {}, nodes: {} }
  end

  def node_file_ids(intent_dir)
    Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort.filter_map do |path|
      NodeFile.parse(path)[:node]
    end
  end

  def node_file_path_for(intent_dir, id)
    Dir.glob(File.join(intent_dir, "nodes", "*.md")).sort.find do |path|
      NodeFile.parse(path)[:node] == id
    end
  end

  def node_entry(intent_dir, id, declared_ids, entries)
    file_path = node_file_path_for(intent_dir, id)
    parsed = file_path ? NodeFile.parse(file_path) : nil
    kind = (parsed && parsed[:kind]) || KIND_BY_PREFIX[id.to_s[0]]
    title = (parsed && title_from_body(parsed[:body])) || id.to_s

    subject_entries = entries.select { |e| e[:subject] == id }
    non_torn = subject_entries.reject { |e| e[:torn] }
    state = non_torn.empty? ? "planned" : NodeLedger.resolved_state(non_torn.last[:state])
    done_entry = non_torn.select { |e| e[:state] == "done" }.last
    fields = done_entry ? done_entry[:fields] : {}
    retries = non_torn.count { |e| e[:state] == "failed_verification" }

    {
      declared: declared_ids.include?(id),
      file_present: !file_path.nil?,
      kind: kind,
      title: title,
      state: state,
      fields: fields,
      retries: retries,
    }
  end

  def title_from_body(body)
    return nil unless body

    line = body.to_s.each_line.find { |l| l.start_with?("#") }
    return nil unless line

    m = line.strip.match(TITLE_LINE_RE)
    m && m[1].strip
  end
end
