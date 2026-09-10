# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "node_file"
require_relative "node_ids"
require_relative "graph_edges"
require_relative "graph_file"
require_relative "atomic_write"
require_relative "ready_set"
require_relative "node_ledger"
require_relative "savepoint"
require_relative "work_graph_validator"

# RunnerProposals (intent 340, G7, n6): accepts or refuses what an executor
# proposed in its return (327 D15, D28, D30). The runner mints every node id;
# an executor never sees or picks one. A proposed node is scaffolded from its
# kind's template, its id substituted everywhere the template hard-codes its
# own placeholder (`n1`, `v1`, `d1`, `r1` - the frontmatter key, the H1, and
# the failure-mode matrix heading), and appended to graph.md's ## Graph
# section as a fresh, undispatched line - no ledger line at all, which reads
# as "planned" by construction. A proposed edge is accepted only when both
# endpoints exist (among the already-declared nodes or a node this very call
# is minting), its head is not `running`, and the resulting graph stays
# acyclic (D30); a refusal writes one ledger comment naming which of the
# three failed.
#
# One call, one all-or-nothing write (D15's "nothing is partially written"):
# every proposed node and edge is validated BEFORE anything touches disk. A
# single rejected edge refuses the WHOLE call, leaving graph.md and nodes/
# byte-identical to how #accept found them, and burning no minted id (an id
# is only ever consumed once a node FILE actually exists; NodeIds.taken never
# sees one this call abandoned).
#
# Pure and dependency-injected: the full validator re-run (327 D17's "a mid-
# run scaffold is checked, not merely accepted"), the templates directory,
# the clock and the rename call are all injectable keyword arguments with
# real defaults, so a test never touches a real ~/.plastic install.
module RunnerProposals
  module_function

  KIND_TEMPLATES = {
    "work" => "node-work.md",
    "verify" => "node-verify.md",
    "decision" => "node-decision.md",
    "research" => "node-research.md",
  }.freeze

  # accept(context, proposer:, proposed_nodes:, proposed_edges:, now:,
  # validator:, templates_dir:, renamer:) -> {ok:, minted:, validator:,
  # errors:}. `proposer` names the node whose return carried these proposals
  # - it is used only to attribute the refusal comment; the runner itself
  # decides everything about the proposal's fate.
  def accept(context, proposer:, proposed_nodes: [], proposed_edges: [], now: Time.now,
             validator: WorkGraphValidator.method(:validate), templates_dir: nil,
             renamer: File.method(:rename))
    intent_dir = context.intent_dir
    graph_path = File.join(intent_dir, "graph.md")
    templates_root = templates_dir || File.join(context.plastic_home.to_s, "templates")

    loaded = ReadySet.load_graph(intent_dir)
    declared = loaded[:edges].keys
    status_map = NodeLedger.status_from_content(read_savepoint(intent_dir))

    mint_pool = NodeIds.taken(intent_dir).dup
    node_specs = []

    Array(proposed_nodes).each do |raw|
      spec = stringify(raw)
      kind = spec["kind"].to_s
      template_name = KIND_TEMPLATES[kind]
      unless template_name
        return refuse(intent_dir, proposer, "proposed node kind #{kind.inspect} has no template", now)
      end

      template_path = File.join(templates_root, template_name)
      unless File.exist?(template_path)
        return refuse(intent_dir, proposer, "missing template for kind #{kind.inspect} at #{template_path}", now)
      end

      id = NodeFile.mint_id(kind, mint_pool)
      mint_pool << id
      node_specs << {
        id: id, kind: kind, template_path: template_path,
        needs: Array(spec["needs"]).map(&:to_s),
        files: spec["files"].nil? ? nil : Array(spec["files"]),
        budget: spec["budget"],
      }
    end

    trial_edges = loaded[:edges].dup
    node_specs.each { |s| trial_edges[s[:id]] = s[:needs] }
    known_ids = declared + node_specs.map { |s| s[:id] }

    edge_specs = []
    Array(proposed_edges).each do |raw|
      e = stringify(raw)
      from = e["from"].to_s
      to = e["to"].to_s

      unless known_ids.include?(from) && known_ids.include?(to)
        return refuse(intent_dir, proposer,
                       "edge #{from}->#{to} refused (endpoint_unknown): both ends must be a declared or proposed node", now)
      end

      if status_map.fetch(from, "planned") == "running"
        return refuse(intent_dir, proposer,
                       "edge #{from}->#{to} refused (head_running): #{from} is currently running", now)
      end

      trial = trial_edges.dup
      trial[from] = (trial[from] || []) + [to]
      if GraphEdges.cycle(trial)
        return refuse(intent_dir, proposer,
                       "edge #{from}->#{to} refused (would_cycle): would make the graph cyclic", now)
      end

      trial_edges = trial
      edge_specs << { from: from, to: to }
    end

    node_specs.each { |s| scaffold_node_file(intent_dir, s) }
    if node_specs.any? || edge_specs.any?
      append_to_graph(graph_path, node_specs: node_specs, edge_specs: edge_specs, renamer: renamer)
    end

    { ok: true, minted: node_specs.map { |s| s[:id] }, validator: validator.call(intent_dir), errors: [] }
  end

  # --- node scaffolding --------------------------------------------------

  # A template's own placeholder id ("n1", "v1", ...) is replaced only as a
  # whole token, so minting past 9 (a proposed "n10") never mangles a
  # coincidental substring match.
  def substitute_id(text, old_id, new_id)
    text.to_s.gsub(/(?<![A-Za-z0-9_-])#{Regexp.escape(old_id.to_s)}(?![A-Za-z0-9_-])/, new_id.to_s)
  end

  def scaffold_node_file(intent_dir, spec)
    parsed_template = NodeFile.parse(spec[:template_path])
    old_id = parsed_template[:node]
    raw = File.read(spec[:template_path])
    parts = raw.split("---", 3)
    body = substitute_id(parts[2].to_s, old_id, spec[:id])

    files = spec[:files].nil? ? parsed_template[:files] : spec[:files]
    budget = spec[:budget].nil? ? parsed_template[:budget] : spec[:budget]

    frontmatter = "---\nnode: #{spec[:id]}\nkind: #{spec[:kind]}\nfiles: [#{Array(files).join(', ')}]\nbudget: #{budget}\n---"
    path = File.join(intent_dir, "nodes", "#{spec[:id]}.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{frontmatter}#{body}")
  end
  private_class_method :scaffold_node_file

  # --- graph.md editing ----------------------------------------------------

  # Appends one "- <id> needs <targets>" line per minted node, then applies
  # each accepted edge onto the line (existing or just-appended) whose id
  # matches its `from`, through GraphFile's own public section helpers
  # (section_bounds, section_body, replace_or_append_section - none of them
  # private_class_method'd) so this stays a plain text edit, never a second
  # bespoke parser.
  def append_to_graph(graph_path, node_specs:, edge_specs:, renamer:)
    content = File.read(graph_path)
    bounds = GraphFile.section_bounds(content, "## Graph")
    return unless bounds

    body = GraphFile.section_body(content, "## Graph").to_s
    lines = body.split("\n")

    node_specs.each do |s|
      rendered = s[:needs].empty? ? "nothing" : s[:needs].join(" ")
      lines << "- #{s[:id]} needs #{rendered}"
    end

    edge_specs.each do |e|
      idx = lines.index { |l| l.strip.match?(/\A-\s*#{Regexp.escape(e[:from])}\s+needs\b/) }
      next unless idx

      stripped = lines[idx].strip
      m = stripped.match(/\A-\s*(\S+)\s+needs\s+(.*)\z/)
      targets = m[2].to_s.strip.split(/\s+/)
      targets = [] if targets == ["nothing"]
      targets << e[:to] unless targets.include?(e[:to])
      lines[idx] = "- #{e[:from]} needs #{targets.empty? ? 'nothing' : targets.join(' ')}"
    end

    new_body = lines.join("\n")
    new_content = GraphFile.replace_or_append_section(content, "## Graph", new_body)
    AtomicWrite.write(graph_path, new_content, renamer: renamer)
  end
  private_class_method :append_to_graph

  # --- refusal -------------------------------------------------------------

  # One ledger comment (a plain milestone-style line through Savepoint's own
  # public append primitive, never a state transition - a refused proposal
  # changes nothing about the proposer's own status) naming which of the
  # three checks failed. Dedup'd by (stage, text) like every other such line,
  # so an identical refusal repeated verbatim across retries writes once.
  def refuse(intent_dir, proposer, reason, now)
    Savepoint.append_savepoint_line(intent_dir, "Proposal", "#{proposer}: #{reason}", now)
    { ok: false, minted: [], validator: nil, errors: [reason] }
  end
  private_class_method :refuse

  # --- internals -------------------------------------------------------------

  def stringify(hash)
    (hash || {}).each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
  end
  private_class_method :stringify

  def read_savepoint(intent_dir)
    path = File.join(intent_dir.to_s, "savepoint.md")
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :read_savepoint
end
