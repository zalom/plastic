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

    # Arm.home_for's own docstring says it returns the PARENT of `.plastic`
    # (the OS home, honestly named `home_root` here) - everywhere else in the
    # tree, including CoreIntegrity.check and RunnerProposals' templates_dir,
    # `plastic_home` means the `.plastic` directory itself. Row 9.5: append
    # it once, here, so every consumer of `context.plastic_home` sees the
    # same directory `manifest.json` and `templates/` actually live in.
    home_root = safe(errors, "plastic home") { Arm.home_for(dir, home: home) } || home
    plastic_home = File.join(home_root, ".plastic")

    resolved_session = safe(errors, "session") do
      resolve_owning_session(dir, explicit: session, env_session: env, store: store, intent_id: intent_id)
    end

    # Arm.worktree_block's own `home:` parameter is the OS-home fallback
    # `Arm.home_for` takes (it re-derives home_for internally), not the
    # `.plastic` directory - pass it `home_root`, never `plastic_home`.
    worktree_block = safe(errors, "worktree") { Arm.worktree_block(intent_dir: dir, home: home_root) } || {}

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
  #
  # M8: Detail carries the readiness BLOCKERS only for a node still in play;
  # a TERMINAL node (done, superseded, abandoned) instead renders its own
  # last transition's fields, so a `done` node reads its commit rather than
  # the nonsense "n1 is done, not eligible to enter running" every later
  # transition used to rewrite it to.
  def render_status(context)
    rows = status(context)
    graph_rows = rows.map do |id, view|
      { node: id, state: view[:state], detail: detail_for(view) }
    end
    GraphFile.write_status(File.join(context.intent_dir.to_s, "graph.md"), graph_rows)
  end

  def detail_for(view)
    if ReadySet::TERMINAL_STATES.include?(view[:state])
      transition_detail(view[:last_transition])
    else
      Array(view[:blockers]).join("; ")
    end
  end

  def transition_detail(last_transition)
    return "" unless last_transition

    fields = last_transition[:fields] || {}
    fields.map { |k, v| "#{k}=#{v}" }.join(" ")
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

  # safe_load_graph(intent_dir) -> ReadySet.load_graph's own result, or the
  # same {ok: false, edges: {}, nodes: {}, errors: [...]} shape when the
  # graph is not the well-formed UTF-8 ReadySet assumes (post-execution
  # review M9). `step`, `answer` and `rewind` all re-read and re-parse
  # graph.md fresh, after RunnerCore.context's own first, already-guarded
  # read (`safe` above) - a raise from THAT second read crossed the
  # runner's boundary as a raw stack trace. The one safe loader every such
  # call site uses now, so a graph that goes bad between two reads refuses
  # cleanly everywhere, not just here.
  def safe_load_graph(intent_dir)
    ReadySet.load_graph(intent_dir)
  rescue StandardError => e
    { ok: false, edges: {}, nodes: {}, errors: ["graph.md could not be read: #{e.message}"] }
  end
end
