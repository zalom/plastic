# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "node_ledger"
require_relative "ready_set"
require_relative "node_file"
require_relative "node_ids"
require_relative "graph_file"
require_relative "atomic_write"
require_relative "runner_core"
require_relative "worktree"

# RunnerRewind (intent 340, G7, n6): resets the intent branch to a node's own
# recorded commit, marks every downstream node superseded (its evidence no
# longer stands once the code it was built on is gone), and respins the
# rewound node itself the same way RunnerAnswer's hard-cap path does - never
# a plain `planned` line, because `failed_verification_count` is counted per
# subject id over the WHOLE ledger and never resets; only a brand new id
# starts clean.
#
# Internal, confirm-gated (327 D15's rewind clause): `confirm:` must be
# explicitly true, and the whole intent must be quiescent (no `running` node
# anywhere) before a branch reset is safe to make - resetting the branch
# under a live executor's own worktree would move the base it is building on
# out from under it.
#
# Pure and dependency-injected: every git call goes through an injected
# `runner:` (default Worktree::ShellRunner), always `-C <path>`, never cwd;
# the clock and the rename call are injectable the same way every other
# runner_* module here already is.
module RunnerRewind
  module_function

  def rewind(context, node:, confirm:, now: Time.now, ledger: NodeLedger,
             runner: Worktree::ShellRunner.new, renamer: File.method(:rename))
    node = node.to_s
    return refusal("confirm_required") unless confirm

    intent_dir = context.intent_dir
    loaded = ReadySet.load_graph(intent_dir)
    edges = loaded[:edges]
    nodes_decl = loaded[:nodes]
    before_content = read_savepoint(intent_dir)
    entries = NodeLedger.entries_from_content(before_content)
    status_map = NodeLedger.status_from_content(before_content)

    return refusal("a_node_is_running") if status_map.value?("running")

    commit = last_commit(entries, node)
    return refusal("no_recorded_commit") if commit.nil? || commit.to_s.strip.empty?

    return refusal("no_intent_worktree") if blank?(context.worktree)

    reset = runner.run("-C", context.worktree, "reset", "--hard", commit)
    return refusal("git_reset_failed", detail: reset.stderr.to_s.strip) unless reset.success?

    downstream = downstream_of(node, edges)
    downstream.each do |d|
      ledger.append_transition(savepoint_path(intent_dir), subject: d, state: "superseded",
                                fields: { by: node }, now: now)
    end

    succ_id = respin(intent_dir, node, nodes_decl, edges, ledger: ledger, now: now, renamer: renamer)

    RunnerCore.render_status(context)

    {
      ok: true, reset_to: commit, superseded: downstream, respun_to: succ_id, errors: [],
      newly_ready: newly_ready(intent_dir, before_content: before_content, before_nodes: nodes_decl,
                                before_edges: edges),
    }
  end

  # --- downstream: everything that, directly or transitively, needs the
  # rewound node - the mirror of ReadySet.critical_paths' own successors map.

  def downstream_of(node, edges)
    successors = Hash.new { |h, k| h[k] = [] }
    edges.each { |id, targets| (targets || []).each { |t| successors[t] << id } }

    seen = []
    stack = successors[node].dup
    until stack.empty?
      n = stack.pop
      next if seen.include?(n)

      seen << n
      stack.concat(successors[n] || [])
    end
    seen.sort
  end
  private_class_method :downstream_of

  def last_commit(entries, node)
    last = entries.select { |e| !e[:torn] && e[:subject] == node && e[:state] == "done" }.last
    last && (last[:fields] || {})["commit"]
  end
  private_class_method :last_commit

  # --- the respin (327 D22, same shape as RunnerAnswer's hard-cap path) ------

  def respin(intent_dir, node, nodes_decl, edges, ledger:, now:, renamer:)
    decl = nodes_decl[node] || {}
    kind = decl[:kind]
    node_path = ReadySet.find_node_path(intent_dir, node)
    parsed = NodeFile.parse(node_path)

    mint_pool = NodeIds.taken(intent_dir).dup
    succ_id = NodeFile.mint_id(kind, mint_pool)

    raw = File.read(node_path)
    parts = raw.split("---", 3)
    body = substitute_id(parts[2].to_s, node, succ_id)
    files = parsed[:files] || decl[:files] || []
    budget = parsed[:budget]

    frontmatter = "---\nnode: #{succ_id}\nkind: #{kind}\nfiles: [#{Array(files).join(', ')}]\nbudget: #{budget}\n---"
    succ_path = File.join(intent_dir, "nodes", "#{succ_id}.md")
    FileUtils.mkdir_p(File.dirname(succ_path))
    File.write(succ_path, "#{frontmatter}#{body}")

    append_graph_line(File.join(intent_dir, "graph.md"), succ_id, edges[node] || [], renamer: renamer)

    ledger.append_transition(savepoint_path(intent_dir), subject: node, state: "superseded",
                              fields: { by: succ_id }, now: now)

    succ_id
  end
  private_class_method :respin

  def append_graph_line(graph_path, id, needs, renamer:)
    content = File.read(graph_path)
    body = GraphFile.section_body(content, "## Graph").to_s
    lines = body.split("\n")
    rendered = needs.empty? ? "nothing" : needs.join(" ")
    lines << "- #{id} needs #{rendered}"
    new_body = lines.join("\n")
    new_content = GraphFile.replace_or_append_section(content, "## Graph", new_body)
    AtomicWrite.write(graph_path, new_content, renamer: renamer)
  end
  private_class_method :append_graph_line

  def substitute_id(text, old_id, new_id)
    text.to_s.gsub(/(?<![A-Za-z0-9_-])#{Regexp.escape(old_id.to_s)}(?![A-Za-z0-9_-])/, new_id.to_s)
  end
  private_class_method :substitute_id

  def newly_ready(intent_dir, before_content:, before_nodes:, before_edges:)
    after = ReadySet.load_graph(intent_dir)
    after_content = read_savepoint(intent_dir)

    after[:nodes].keys.select do |id|
      was = before_nodes.key?(id) &&
            ReadySet.ready?(content: before_content, subject: id, graph: { edges: before_edges },
                             nodes: before_nodes)[:ready]
      now_ready = ReadySet.ready?(content: after_content, subject: id, graph: { edges: after[:edges] },
                                   nodes: after[:nodes])[:ready]
      now_ready && !was
    end.sort
  end
  private_class_method :newly_ready

  def refusal(reason, detail: nil)
    { ok: false, reason: reason, detail: detail, reset_to: nil, superseded: [], respun_to: nil, newly_ready: [] }
  end
  private_class_method :refusal

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
  private_class_method :blank?

  def read_savepoint(intent_dir)
    path = savepoint_path(intent_dir)
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :read_savepoint

  def savepoint_path(intent_dir)
    File.join(intent_dir.to_s, "savepoint.md")
  end
  private_class_method :savepoint_path
end
