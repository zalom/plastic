# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "yaml"
require_relative "ready_set"
require_relative "node_ledger"
require_relative "node_file"
require_relative "node_packet"
require_relative "node_worktree"
require_relative "work_graph_validator"
require_relative "runner_core"
require_relative "runner_policy"
require_relative "worktree"
require_relative "savepoint"
require_relative "guarded_append"
require_relative "harness_adapter"

# RunnerDispatch (intent 340, G7, n5): validates the graph, computes the
# ready set, applies RunnerPolicy, mints leases, builds packets, writes
# `running`, and returns the dispatch plan `step` prints. Never spawns an
# agent itself (327 D42): the session does that from the plan this returns.
#
# Pure and dependency-injected down to the clock: every side effect - the
# full validator, the ready-set analyzer, the packet builder, the worktree
# module, the ledger write, git itself - is an injectable keyword argument
# with a real default, so a test never touches a real repository or a real
# filesystem outside its own tmpdir.
module RunnerDispatch
  module_function

  DEFAULT_LIMIT = 2

  # The return-schema instruction (327 D5): rides in the dispatch PLAN, never
  # inside the packet, so `packet=<sha>` keeps naming a reproducible input
  # (matrix row 5.23). NodeReturn.parse (n4) is this text's implementation.
  RETURN_CONTRACT = <<~TEXT.freeze
    RETURN CONTRACT: reply with exactly one YAML document as your final
    message, nothing else around it. Keys: node, status, commit, summary,
    findings, proposed_nodes, proposed_edges, question, reason. status is one
    of done, failed_verification, needs_decision, blocked. done requires
    commit; needs_decision requires question; failed_verification and
    blocked require reason. Anything that does not parse under this closed
    schema is refused as failed_verification reason=return_unparsable.
  TEXT

  HARD_CAP_RE = /\Ais at its dispatch cap \((\d+)\/(\d+)\)\z/.freeze

  # D8 (355, n6): the agent every dispatched, non-decision node names - a
  # role, never a harness (matrix 6.5), and never `plastic-advisor`, which
  # stays a deliberate, never-auto-dispatched consultation agent.
  SPAWN_AGENT = "plastic-executor"

  # matrix 6.1/6.2: one spawn block per dispatched node - agent, the model
  # RunnerPolicy.model_for resolved, the packet path, the one test command
  # (NodePacket.test_command_block, n4), and the call cap (n2) - fenced so a
  # session pastes it straight into the Agent tool (327 D42: the runner
  # itself never spawns).
  def spawn_block(model:, packet:, test_command:, call_cap:, agent: SPAWN_AGENT)
    lines = ["agent: #{agent}", "model: #{model}", "packet: #{packet}", test_command,
             NodePacket.call_cap_sentence(call_cap)]
    (["```"] + lines + ["```"]).join("\n")
  end

  # dispatch(context, limit:) -> a result hash. Always carries :ok, :reason,
  # :errors, :rearm_command, :dispatched, :stop, :parked, :status, :blockers,
  # :plan - fields that do not apply to a given outcome stay nil/empty rather
  # than being omitted, so a caller never has to guard with `dig`.
  def dispatch(context, limit: DEFAULT_LIMIT, now: Time.now, config: {}, harness: nil, caps: ReadySet::DEFAULT_CAPS,
               validator: WorkGraphValidator.method(:validate),
               ready_analyzer: ReadySet.method(:analyze),
               packet_builder: NodePacket.method(:build),
               worktree: NodeWorktree,
               ledger: NodeLedger,
               runner: Worktree::ShellRunner.new,
               harness_adapter: HarnessAdapter)
    intent_dir = context.intent_dir
    savepoint_path = File.join(intent_dir.to_s, "savepoint.md")

    # Intent 340b, G7c, n1, rows 1.19/1.20/D21: resolved ONCE for the whole
    # step through HarnessAdapter, never a literal - `harness:` (this call's
    # `--harness` override, or nil) wins over `config`'s own `agent.type`.
    # Every node this call dispatches carries the SAME value, and the
    # caller (scripts/runner) reads it back off the report to pick which
    # harness's block to render.
    harness_key = harness_adapter.resolve_key(config: config, override: harness)

    # Row 5.31/5.32: this is RunnerDispatch's OWN lock check, never a shelled
    # `node-transition` call - append_transition below is used in-process
    # (RunnerAbsorb's own pattern), so nothing here inherits node-transition's
    # CLI-level lock refusal (exit 4) for free.
    return lock_refusal(intent_dir) unless context.session

    content = read_savepoint(savepoint_path)
    entries = NodeLedger.entries_from_content(content)

    # Row 5.1/5.2/5.3: the full validator runs only when the ledger holds no
    # `running` line for ANY node yet (327 D17's exact precondition) - every
    # later dispatch skips it and relies on the cheaper re-read below.
    #
    # M9: both the validator and the ready analyzer re-parse graph.md fresh
    # (RunnerCore.context's own first read, already guarded, is not reused
    # here on purpose - row 5.4), and a malformed graph.md - non-UTF-8 bytes,
    # say - raises out of both rather than reporting :ok false. Guarded here
    # so `step` refuses cleanly instead of dying with a raw stack trace.
    if entries.none? { |e| e[:state] == "running" }
      full = safe_validate(validator, intent_dir)
      return invalid_graph_result(full[:errors]) unless full[:ok]
    end

    # Row 5.4: re-read graph.md and cycle-check on EVERY dispatch, first or
    # not. ReadySet.analyze re-parses graph.md and nodes/ from disk itself,
    # so nothing here trusts `context.graph`, which was resolved once,
    # before this step even started.
    analysis = safe_analyze(ready_analyzer, intent_dir, now: now, caps: caps)
    return invalid_graph_result(analysis[:errors]) unless analysis[:ok]

    loaded = RunnerCore.safe_load_graph(intent_dir)
    return invalid_graph_result(loaded[:errors]) unless loaded[:ok]

    edges = loaded[:edges]
    nodes_decl = loaded[:nodes]

    # Minor 9: count `running` only for NODE subjects - an `Intent` subject
    # in a running-like state must never eat a dispatch slot meant for the
    # concurrency ceiling over nodes.
    running_count = NodeLedger.status_from_content(content).count do |subject, s|
      s == "running" && subject.to_s.match?(Savepoint::NODE_SUBJECT_RE)
    end
    slots = [limit.to_i - running_count, 0].max

    dispatched = []
    parked = []
    stop = nil
    packet_failures = []
    ceiling_blocked = false

    analysis[:ranked_ready].each do |row|
      break if stop

      node = row[:id].to_s
      kind = (nodes_decl[node] || {})[:kind] || row[:kind]

      # Row 5.33: the ONLY overlap check anywhere in this loop - re-evaluated
      # against the latest on-disk content on every iteration, so a sibling
      # this very step just dispatched (its `running` line already written)
      # is seen by the very next candidate, without RunnerDispatch ever
      # carrying its own copy of the overlap rule.
      live = ReadySet.ready?(content: content, subject: node, graph: { edges: edges }, nodes: nodes_decl,
                              caps: caps)
      next unless live[:ready]

      if kind.to_s == "decision"
        stop = write_decision_stop(savepoint_path, intent_dir, node, ledger: ledger, now: now)
        content = read_savepoint(savepoint_path)
        next
      end

      if RunnerPolicy.at_retry_cap?(entries, node, kind)
        parked << write_retry_cap_park(savepoint_path, intent_dir, node, kind, entries, ledger: ledger, now: now)
        content = read_savepoint(savepoint_path)
        entries = NodeLedger.entries_from_content(content)
        next
      end

      # M10: a ready node that cannot dispatch because every slot is taken
      # is QUEUED, not stalled - the graph can still continue, it is merely
      # waiting on the ceiling, matrix row 10.13.
      if slots <= 0
        ceiling_blocked = true
        next
      end

      result = dispatch_one(context, node: node, kind: kind, now: now, config: config, harness: harness_key,
                             caps: caps, edges: edges, nodes_decl: nodes_decl, packet_builder: packet_builder,
                             worktree: worktree, ledger: ledger, runner: runner)
      if result[:packet_build_failed]
        packet_failures << result
        next
      end
      next unless result[:ok]

      dispatched << result[:entry]
      slots -= 1
      content = read_savepoint(savepoint_path)
      entries = NodeLedger.entries_from_content(content)
    end

    # Row 5.34: re-render graph.md's ## Status once, after every write this
    # step made, mirroring RunnerAbsorb's own single call after its own
    # transition.
    RunnerCore.render_status(context) if dispatched.any? || stop || parked.any?

    build_report(context: context, dispatched: dispatched, stop: stop, parked: parked,
                 ceiling_blocked: ceiling_blocked, packet_failures: packet_failures, running_count: running_count,
                 harness: harness_key)
  end

  # --- guarded re-entries into graph.md (M9) ----------------------------------

  def safe_validate(validator, intent_dir)
    validator.call(intent_dir)
  rescue StandardError => e
    { ok: false, errors: ["graph.md could not be read: #{e.message}"] }
  end
  private_class_method :safe_validate

  def safe_analyze(ready_analyzer, intent_dir, now:, caps:)
    ready_analyzer.call(intent_dir, now: now, caps: caps)
  rescue StandardError => e
    { ok: false, errors: ["graph.md could not be read: #{e.message}"] }
  end
  private_class_method :safe_analyze

  # --- one node's whole dispatch (packet, lease, `running`) -------------------

  def dispatch_one(context, node:, kind:, now:, config:, harness:, caps:, edges:, nodes_decl:, packet_builder:,
                    worktree:, ledger:, runner:)
    intent_dir = context.intent_dir
    savepoint_path = File.join(intent_dir.to_s, "savepoint.md")

    holder = context.session
    model = RunnerPolicy.model_for(kind, config: config)
    expires = RunnerPolicy.lease_expires(kind, now: now)
    calls_cap = RunnerPolicy.call_cap(kind, config: config)

    # Row 10.16/M13: recorded BEFORE provisioning - a worktree this dispatch
    # finds already on disk (kept there by a prior failed_verification
    # attempt, D7) must never be the one a later rollback in this same call
    # deletes; only a worktree THIS call actually creates may be rolled back.
    pre_existing_worktree = worktree_pre_existing?(worktree, context, node, kind)

    # Row 5.16/5.29: only a `work` node gets a worktree, and this is the
    # node-scoped `worktree_reader:` D23 injects into NodePacket.build - it
    # names THIS node's own worktree and branch, never the intent's.
    provisioned = RunnerPolicy.worktree?(kind) ? worktree.provision(context, node: node, kind: kind, runner: runner)
                                                : unprovisioned
    node_reader = lambda do |intent_dir:|
      { "code" => provisioned[:path], "code_branch" => provisioned[:branch], "provisioned" => !!provisioned[:provisioned] }
    end

    # Row 5.18: build the packet BEFORE writing `running` - a `running` line
    # naming bytes that do not exist yet is worse than a packet nobody reads.
    # Row 5.30: `force: true` always - a fresh attempt number this dispatch
    # computes is, by construction, never one `running` has already claimed,
    # so an existing file at that path is always an orphan from a step that
    # crashed between building the packet and writing `running`, safe to
    # overwrite outright.
    # Row 5.20/10.8: the node's own declared budget: (M7) - nil when the node
    # names none, in which case NodePacket.build falls back to its own
    # default (row 10.9).
    build_result = packet_builder.call(intent_dir: intent_dir, node: node, holder: holder, expires: expires,
                                        model: model, force: true, worktree_reader: node_reader,
                                        budget_tokens: node_declared_budget(intent_dir, node), call_cap: calls_cap)
    unless build_result[:ok]
      # M6: a failed packet build never leaves an orphan worktree behind, and
      # its errors travel back up so the step's report can name the node and
      # the reason instead of a bare "stalled" (row 10.6/10.7).
      rollback_dispatch(context, node: node, kind: kind, packet_path: build_result[:path], runner: runner,
                         worktree: worktree, created_this_dispatch: !pre_existing_worktree)
      return { ok: false, packet_build_failed: true, node: node, errors: build_result[:errors] }
    end

    precondition = lambda do |c|
      ReadySet.ready?(content: c, subject: node, graph: { edges: edges }, nodes: nodes_decl, caps: caps)[:ready]
    end
    # Row 1.19/1.20/D21: harness= rides alongside model= on every `running`
    # line, resolved once by the caller through HarnessAdapter and threaded
    # straight through here - never re-resolved, never a literal.
    fields = { holder: holder, expires: expires, packet: build_result[:sha], model: model, harness: harness,
               calls: calls_cap }

    result = begin
      ledger.append_transition(savepoint_path, subject: node, state: "running", fields: fields, now: now,
                                precondition: precondition)
    rescue GuardedAppend::Unavailable
      :unavailable
    end

    # Row 5.20: a refused (or unavailable) `running` write rolls back both
    # side effects this method already produced - the node never ran, so
    # nothing may act like it did.
    unless result == :written
      rollback_dispatch(context, node: node, kind: kind, packet_path: build_result[:path], runner: runner,
                         worktree: worktree, created_this_dispatch: !pre_existing_worktree)
      return { ok: false }
    end

    test_command = NodePacket.test_command_block(intent_dir: intent_dir, files: (nodes_decl[node] || {})[:files])
    spawn = spawn_block(model: model, packet: build_result[:path], test_command: test_command, call_cap: calls_cap)

    {
      ok: true,
      entry: { node: node, kind: kind.to_s, role: role_for(kind), model: model, worktree: provisioned[:path],
                packet: build_result[:path], spawn: spawn },
    }
  end

  # The node's own declared budget: (frontmatter), or nil when it names
  # none - M7. Parsed directly off the node file, never through
  # `nodes_decl` (ReadySet.load_graph's own decl hash carries only kind and
  # files, never budget), so this stays independent of that module.
  def node_declared_budget(intent_dir, node)
    path = ReadySet.find_node_path(intent_dir, node)
    return nil unless path

    nf = NodeFile.parse(path)
    nf[:ok] ? nf[:budget] : nil
  end
  private_class_method :node_declared_budget

  # true iff a `work` node's own worktree already exists BEFORE this call
  # provisions anything - the pre-check `rollback_dispatch` needs to tell a
  # worktree this dispatch created from one it merely found (row 10.16).
  def worktree_pre_existing?(worktree, context, node, kind)
    return false unless RunnerPolicy.worktree?(kind)

    p = worktree.paths(context, node: node)
    !!(p && p["path"] && Dir.exist?(p["path"]))
  end
  private_class_method :worktree_pre_existing?

  def role_for(kind)
    kind.to_s == "verify" ? "advisor" : "executor"
  end

  def unprovisioned
    { ok: true, path: nil, branch: nil, provisioned: false }
  end
  private_class_method :unprovisioned

  # Row 10.16/M13: `created_this_dispatch:` gates the worktree half of the
  # rollback - a worktree this call did not create (kept on disk by a prior
  # attempt's failed_verification, D7) is never touched, only a packet this
  # call's own `packet_builder` may have written is ever deleted.
  def rollback_dispatch(context, node:, kind:, packet_path:, runner:, worktree:, created_this_dispatch:)
    File.delete(packet_path) if packet_path && File.exist?(packet_path)
    return unless RunnerPolicy.worktree?(kind)
    return unless created_this_dispatch

    p = worktree.paths(context, node: node)
    return if p["path"].nil? || !Dir.exist?(p["path"])

    Worktree.remove_worktree(runner, repo: p["repo"], worktree: p["path"])
    Worktree.prune(runner, repo: p["repo"])
  end
  private_class_method :rollback_dispatch

  # --- decision stop and the retry-cap park -----------------------------------

  # Row 5.9/5.10: a ready decision node is never dispatched - it stops the
  # WHOLE step (any node ranked after it this step is simply not reached)
  # and writes its own `needs_decision` line so it reads that way from
  # `status` too, carrying the exact `runner answer` command that clears it.
  def write_decision_stop(savepoint_path, intent_dir, node, ledger:, now:)
    question = decision_question(intent_dir, node)
    safe_append(ledger, savepoint_path, node, "needs_decision", { question: question }, now: now)
    { reason: "decision", node: node, question: question, answer_command: answer_command(intent_dir, node) }
  end
  private_class_method :write_decision_stop

  # Row 5.11/5.27/5.28: a node at RunnerPolicy's SOFT cap is parked at
  # `needs_decision` with a synthesized `question=` rather than dispatched a
  # further time, carrying the same `runner answer` shape.
  def write_retry_cap_park(savepoint_path, intent_dir, node, kind, entries, ledger:, now:)
    count = RunnerPolicy.retry_count(entries, node)
    cap = RunnerPolicy.retry_cap(kind)
    question = "#{node} has failed verification #{count} time(s), its #{kind} retry cap is #{cap}; " \
               "retry, rewind, or abandon it?"
    safe_append(ledger, savepoint_path, node, "needs_decision", { question: question }, now: now)
    { reason: "retry_cap", node: node, question: question, answer_command: answer_command(intent_dir, node) }
  end
  private_class_method :write_retry_cap_park

  def safe_append(ledger, savepoint_path, node, state, fields, now:)
    ledger.append_transition(savepoint_path, subject: node, state: state, fields: fields, now: now)
  rescue GuardedAppend::Unavailable
    nil
  end
  private_class_method :safe_append

  def decision_question(intent_dir, node)
    path = ReadySet.find_node_path(intent_dir, node)
    fallback = "#{node} needs an owner decision; see its ## Question section"
    return fallback unless path

    nf = NodeFile.parse(path)
    return fallback unless nf[:ok]

    section = NodeFile.split_by_headings(nf[:body]).find { |(heading, _)| heading.to_s.strip == "## Question" }
    text = section && section[1].to_s.strip
    text && !text.empty? ? squash(text) : fallback
  end
  private_class_method :decision_question

  def squash(text)
    text.to_s.gsub(/\s+/, " ").strip
  end
  private_class_method :squash

  # Row 5.10/5.28: the one command shape every stop and every park prints,
  # matching scripts/runner's own published usage
  # (`runner <step|status|answer> <intent_dir> [--node ID] [--answer TEXT]`).
  def answer_command(intent_dir, node)
    "runner answer #{intent_dir} --node #{node} --answer \"<your answer>\""
  end

  # Row 5.32: re-arms delivery.lock for a resumed session with a new id -
  # `plastic-lock arm` is the shipped command that takes ownership again.
  def rearm_command(intent_dir)
    "plastic-lock arm --intent-dir #{intent_dir}"
  end

  # --- refusals and the report -------------------------------------------------

  def empty_result
    { ok: true, reason: nil, errors: [], rearm_command: nil, dispatched: [], stop: nil, parked: [],
      status: nil, blockers: [], plan: nil, harness: nil }
  end
  private_class_method :empty_result

  def lock_refusal(intent_dir)
    empty_result.merge(ok: false, reason: "lock_not_held", rearm_command: rearm_command(intent_dir))
  end
  private_class_method :lock_refusal

  def invalid_graph_result(errors)
    empty_result.merge(ok: false, reason: "invalid_graph", errors: Array(errors))
  end
  private_class_method :invalid_graph_result

  def build_report(context:, dispatched:, stop:, parked:, ceiling_blocked: false, packet_failures: [],
                    running_count: 0, harness: nil)
    base = empty_result.merge(dispatched: dispatched, stop: stop, parked: parked,
                               plan: render_plan(dispatched), harness: harness)

    if dispatched.any?
      base.merge(status: "dispatched")
    elsif stop
      base.merge(status: "needs_decision")
    elsif ceiling_blocked || running_count.to_i.positive?
      # M10/v2 NEW-7: a ready node waiting on the concurrency ceiling is one
      # shape of "still in flight" - a graph where every ready node is
      # ALREADY running (no candidate ever reaches the ceiling check at all,
      # so `ceiling_blocked` never sets) is the ordinary busy case, and it
      # used to fall all the way through to `stalled`. Any node genuinely
      # `running` means the graph can still continue on its own.
      base.merge(status: "queued")
    else
      # Row 5.25: complete iff EVERY declared node is terminal - an empty
      # ready set from parked/blocked nodes must never read as finished.
      complete = RunnerCore.complete?(context)
      if complete
        base.merge(status: "complete")
      else
        # M6/row 10.7: a failed packet build writes no ledger line at all,
        # so `named_blockers` (ledger-derived) never sees it on its own -
        # its own node and reason are named here so `stalled` never prints
        # bare.
        blockers = named_blockers(context) + packet_failures.map { |f| packet_failure_blocker(f) }
        base.merge(status: "stalled", blockers: blockers)
      end
    end
  end
  private_class_method :build_report

  def packet_failure_blocker(failure)
    "#{failure[:node]}: packet build failed (#{Array(failure[:errors]).join('; ')})"
  end
  private_class_method :packet_failure_blocker

  # Row 5.25a/5.26: every unfinished node's own blockers, with ReadySet's
  # hard-attempt-cap wording renamed so it reads as the named backstop it is
  # (D22: the exit here is `runner answer`, never another dispatch), rather
  # than one more indistinguishable blocker line.
  def named_blockers(context)
    intent_dir = context.intent_dir
    rows = RunnerCore.status(context)
    rows.each_with_object([]) do |(id, view), out|
      next if ReadySet::TERMINAL_STATES.include?(view[:state])

      view[:blockers].each { |b| out << name_blocker(intent_dir, id, b) }
    end
  end
  private_class_method :named_blockers

  def name_blocker(intent_dir, id, blocker)
    rest = blocker.to_s.sub(/\A#{Regexp.escape(id)} /, "")
    m = rest.match(HARD_CAP_RE)
    return "#{id}: #{blocker}" unless m

    "#{id} has reached its hard attempt backstop (#{m[1]}/#{m[2]}) - #{answer_command(intent_dir, id)}"
  end
  private_class_method :name_blocker

  # Row 5.22/5.23/5.24: one machine-readable (YAML) document naming, per
  # dispatched node, the packet path, the model, the worktree, the kind and
  # the role, plus the return contract ONCE at the top level - never inside
  # any one node's packet. Row 6.4: "spawn" carries the same, already fully
  # rendered spawn block for each dispatched node in order, so any reader of
  # this data (YAML today, JSON if it is ever re-serialized) finds it under
  # `spawn` rather than re-deriving it from the other fields.
  def render_plan(dispatched)
    return nil if dispatched.empty?

    YAML.dump(
      "return_contract" => RETURN_CONTRACT,
      "dispatch" => dispatched.map do |d|
        { "node" => d[:node], "kind" => d[:kind], "role" => d[:role], "model" => d[:model],
          "worktree" => d[:worktree], "packet" => d[:packet] }
      end,
      "spawn" => dispatched.map { |d| d[:spawn] }
    )
  end
  private_class_method :render_plan

  def read_savepoint(path)
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :read_savepoint
end
