# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "node_ledger"
require_relative "ready_set"
require_relative "graph_file"
require_relative "atomic_write"
require_relative "node_file"
require_relative "node_ids"
require_relative "runner_core"

# RunnerAnswer (intent 340, G7, n6): closes a decision node into graph.md's
# ## Decisions (C26), or unparks a work node the runner parked at
# `needs_decision` (327 D22). Both share one precondition - the target must
# currently BE at `needs_decision` - and one shape of input: a non-empty
# owner answer.
#
# A decision node writes its text into ## Decisions through
# GraphFile.append_decision (temp-plus-rename, matrix row 6.7) and closes
# with `done verdict=answered`. Any other kind unparks instead:
# `READY_PRIOR_STATES` (ready_set.rb) accepts `planned` and
# `failed_verification` back into dispatch, so below ReadySet::DEFAULT_CAPS'
# HARD attempt backstop, writing `planned` is enough. At or above it, a
# plain `planned` line changes nothing about `failed_verification_count`
# (counted per subject over the WHOLE ledger, never reset) - only a brand
# new subject id starts clean, so the node is superseded and a successor is
# minted carrying its body, files and needs across.
#
# Pure and dependency-injected down to the clock and the rename call; every
# test here drives a real tmpdir intent directory, never a real ~/.plastic
# install.
module RunnerAnswer
  module_function

  def answer(context, node:, text:, now: Time.now, ledger: NodeLedger,
             caps: ReadySet::DEFAULT_CAPS, renamer: File.method(:rename))
    node = node.to_s
    intent_dir = context.intent_dir
    graph_path = File.join(intent_dir, "graph.md")

    return refusal("empty_answer") if text.to_s.strip.empty?

    loaded = ReadySet.load_graph(intent_dir)
    nodes_decl = loaded[:nodes]
    edges = loaded[:edges]
    before_content = read_savepoint(intent_dir)
    entries = NodeLedger.entries_from_content(before_content)
    current_state = NodeLedger.status_for_content(before_content, node)

    return refusal("not_parked") unless current_state == "needs_decision"

    kind = (nodes_decl[node] || {})[:kind]
    respun_to = nil

    if kind.to_s == "decision"
      gf = GraphFile.append_decision(graph_path, text.to_s.strip, renamer: renamer)
      return refusal("graph_write_failed", errors: gf[:errors]) unless gf[:ok]

      # A `done` line's attribution (a non-blank `holder=`) is what
      # ReadySet.ready? requires of a needs target before a successor may
      # become ready (NodeLedger.attributed?): an unattributed done line
      # closes the decision node's own status but never releases anything
      # downstream, so the holder is the session driving this very answer.
      fields = { gates: "answer", verdict: "answered" }
      fields[:holder] = context.session unless blank?(context.session)
      result = ledger.append_transition(savepoint_path(intent_dir), subject: node, state: "done",
                                         fields: fields, now: now)
      return refusal("append_failed") unless result == :written
    else
      cap = caps.fetch(kind.to_s) { caps["work"] }
      attempts = ReadySet.attempts_count(entries, node)

      if cap && attempts >= cap
        respun_to = respin(intent_dir, node, nodes_decl, edges, ledger: ledger, now: now, renamer: renamer,
                            holder: context.session)
      else
        fields = {}
        fields[:holder] = context.session unless blank?(context.session)
        result = ledger.append_transition(savepoint_path(intent_dir), subject: node, state: "planned",
                                           fields: fields, now: now)
        return refusal("append_failed") unless result == :written
      end
    end

    RunnerCore.render_status(context)

    {
      ok: true, respun_to: respun_to, errors: [],
      newly_ready: newly_ready(intent_dir, before_content: before_content, before_nodes: nodes_decl, before_edges: edges),
    }
  end

  # --- the hard-cap respin (327 D22) ------------------------------------------

  def respin(intent_dir, node, nodes_decl, edges, ledger:, now:, renamer:, holder: nil)
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

    fields = { by: succ_id }
    fields[:holder] = holder unless blank?(holder)
    ledger.append_transition(savepoint_path(intent_dir), subject: node, state: "superseded",
                              fields: fields, now: now)

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

  # --- what became ready (C26) ------------------------------------------------

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

  def refusal(reason, errors: [])
    { ok: false, reason: reason, errors: errors, respun_to: nil, newly_ready: [] }
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
