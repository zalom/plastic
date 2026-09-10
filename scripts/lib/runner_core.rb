# encoding: UTF-8
# frozen_string_literal: true

require_relative "arm"
require_relative "lock"
require_relative "worktree"
require_relative "ready_set"
require_relative "node_ledger"
require_relative "graph_file"

# RunnerCore (intent 340, G7, n1): the shared context every scripts/runner
# verb needs, resolved once, plus the two read-only queries (status,
# complete?) and the one write (render_status) this node ships. Session
# resolution mirrors NodeTransition.resolve_owning_session
# (scripts/node-transition) exactly, so `running`'s ownership rule and the
# runner's own idea of "who holds this intent" never drift apart.
#
# Pure and dependency-injected: #context takes intent_dir:, home:, and
# optional session:/env: overrides (the CLI passes the real
# ENV["CLAUDE_CODE_SESSION_ID"] at its own boundary, the same place
# node-transition's main reads it, never inside this library). It never
# raises across its boundary: every field is resolved independently, so a
# missing or malformed graph.md lands in `errors` and every other field
# still resolves. #status and #complete? read the filesystem but write
# nothing; #render_status is the one write, and it goes through
# GraphFile.write_status, the existing atomic writer.
module RunnerCore
  module_function

  Context = Struct.new(
    :intent_dir, :intent_id, :intent_slug, :store, :plastic_home,
    :session, :worktree, :worktree_branch, :graph, :errors,
    keyword_init: true
  )

  def context(intent_dir:, home: Dir.home, session: nil, env: ENV["CLAUDE_CODE_SESSION_ID"])
    dir = File.expand_path(intent_dir.to_s)
    errors = []

    intent_id = safe(errors, "intent id") { Arm.intent_id_for(dir) }
    intent_slug = safe(errors, "intent slug") { Worktree.slug_from_dir(dir) }
    store = safe(errors, "store") { Arm.store_for(dir) }
    plastic_home = safe(errors, "plastic home") { Arm.home_for(dir, home: home) } || home

    resolved_session = safe(errors, "session") do
      resolve_owning_session(dir, explicit: session, env_session: env, store: store, intent_id: intent_id)
    end

    worktree_block = safe(errors, "worktree") { Arm.worktree_block(intent_dir: dir, home: plastic_home) } || {}

    graph = safe(errors, "graph") { ReadySet.load_graph(dir) } ||
            { ok: false, edges: {}, nodes: {}, errors: ["graph could not be resolved"] }
    errors.concat(graph[:errors] || []) unless graph[:ok]

    Context.new(
      intent_dir: dir,
      intent_id: intent_id,
      intent_slug: intent_slug,
      store: store,
      plastic_home: plastic_home,
      session: resolved_session,
      worktree: worktree_block["code"],
      worktree_branch: worktree_block["code_branch"],
      graph: graph,
      errors: errors
    )
  end

  # Mirrors NodeTransition.resolve_owning_session (scripts/node-transition,
  # intent 335 G2): an explicit session is authoritative and never falls
  # through (an explicit non-owner is refused outright, never silently
  # granted ownership through a fallback); without it, try env_session, then
  # the derived `auto-` key, keeping the first candidate that actually HOLDS
  # the lock.
  def resolve_owning_session(intent_dir, explicit:, env_session:, store:, intent_id:)
    if explicit && !explicit.to_s.strip.empty?
      return Lock.holds?(intent_dir, session: explicit) ? explicit : nil
    end

    candidates = [env_session, Arm.derive_key(store, intent_id)].reject { |c| c.to_s.strip.empty? }
    candidates.find { |c| Lock.holds?(intent_dir, session: c) }
  end

  # status(context) -> {id => {kind:, state:, ready:, blockers:,
  # last_transition:}} for every node graph.md DECLARES, whether or not it
  # has a ledger line yet (a node with no line reads as "planned", the
  # ledger's own implicit starting state). Writes NOTHING: savepoint.md's
  # content is read once and every node's readiness is evaluated against
  # that one read, mirroring the way node-transition's own precondition
  # never re-reads the file per node.
  def status(context)
    edges = (context.graph || {})[:edges] || {}
    nodes = (context.graph || {})[:nodes] || {}
    content = savepoint_content(context.intent_dir)
    entries = NodeLedger.entries_from_content(content)

    nodes.each_with_object({}) do |(id, decl), rows|
      readiness = ReadySet.ready?(content: content, subject: id, graph: { edges: edges }, nodes: nodes)
      last = entries.select { |e| !e[:torn] && e[:subject] == id }.last

      rows[id] = {
        kind: decl[:kind],
        state: NodeLedger.status_for_content(content, id),
        ready: readiness[:ready],
        blockers: readiness[:blockers],
        last_transition: last,
      }
    end
  end

  # complete?(context) -> true only when EVERY declared node resolves to a
  # terminal state (done, superseded, abandoned). An empty declared-node set,
  # or any node that is merely not-ready (blocked, needs_decision, deferred,
  # or simply not yet attempted), is stalled, not complete - never shortcut
  # to "the ready set is empty".
  def complete?(context)
    rows = status(context)
    return false if rows.empty?

    rows.values.all? { |v| ReadySet::TERMINAL_STATES.include?(v[:state]) }
  end

  # render_status(context) -> GraphFile.write_status's own {ok:, errors:}.
  # One row per node graph.md declares, including a node with no ledger line
  # (which renders "planned"); a graph.md with no ## Status section gets one
  # created, never a raise - both guarantees come from GraphFile.write_status
  # itself, this method only ever supplies the rows.
  def render_status(context)
    rows = status(context)
    graph_rows = rows.map do |id, view|
      { node: id, state: view[:state], detail: Array(view[:blockers]).join("; ") }
    end
    GraphFile.write_status(File.join(context.intent_dir.to_s, "graph.md"), graph_rows)
  end

  def savepoint_content(intent_dir)
    path = File.join(intent_dir.to_s, "savepoint.md")
    File.exist?(path) ? File.read(path) : ""
  end

  def safe(errors, label)
    yield
  rescue StandardError => e
    errors << "#{label}: #{e.message}"
    nil
  end
end
