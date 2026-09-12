# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "time"
require "rbconfig"
require_relative "runner_core"
require_relative "runner_sweep"
require_relative "runner_absorb"
require_relative "runner_dispatch"
require_relative "node_worktree"
require_relative "lock"

# RunnerUntilEmpty (intent 340b, G7c, n7): the Codex loop. `runner
# until-empty` composes `step` and `node-run` itself, since Codex has no
# session on the other end to make the subagent calls `step` only ever
# prints a plan for - dispatch, run at most two `node-run` subprocesses at
# once, absorb each return, and around again, stopping on complete,
# stalled, needs_decision, a refused step, or an iteration cap.
#
# #step_once is one turn - abort-if-merging, the heartbeat, absorb every
# return this call carries (serially, a plain Ruby loop, never a thread),
# reclaim, reap, then dispatch - the same fixed order scripts/runner's own
# `run_step_body` uses, returning data rather than printing it, so #run can
# make its own stop/continue decision instead of scraping stdout. #run is
# the loop: it grows `active` from whatever #step_once actually dispatched
# (already capped at the concurrency ceiling by RunnerDispatch's own
# running-count check, never a second cap layered on top here), spawns one
# real `node-run` subprocess per newly dispatched node, and blocks for AT
# LEAST one of them to finish before it ever calls #step_once again - so an
# absorb is always a single, uncontended call, and a second `node-run`
# finishing while the first is mid-absorb simply waits its own turn as the
# next iteration's `returns`, never as a second in-flight absorb.
#
# A shared `<repo>/.git` between two worktrees is a real `index.lock`
# collision risk at commit time; this module does not try to prevent it by
# serializing the two `node-run` processes (that would throw away the
# concurrency this node exists to deliver) - it records the collision, on
# whichever side actually hit it, and lets the kind's retry cap (already
# built) recover the node on a later attempt.
#
# Pure and dependency-injected: `step:`, `node_run_spawner:` and
# `node_run_waiter:` are keyword seams with real defaults, so a test can
# drive #run entirely off doubles (no real subprocess, no real git repo)
# for every row except the ones that are precisely about real OS
# concurrency or the real CLI arm.
module RunnerUntilEmpty
  module_function

  MAX_CONCURRENCY = 2
  DEFAULT_MAX_ITERATIONS = 200

  NODE_RUN_SCRIPT = File.expand_path(File.join(__dir__, "..", "node-run")).freeze

  # run(context, harness:) -> {status:, iterations:, ...}. `status` is one
  # of complete, stalled, needs_decision, iteration_cap, refused - never
  # anything else, and the loop returns the instant it reaches one of them.
  def run(context, harness: nil, max_iterations: DEFAULT_MAX_ITERATIONS,
          step: method(:step_once), node_run_spawner: method(:spawn_node_run),
          node_run_waiter: method(:wait_for_node_run), out: $stdout)
    active = {}
    pending_returns = {}
    iterations = 0

    loop do
      iterations += 1
      if iterations > max_iterations
        out.puts "until-empty: stopped at the iteration cap (#{max_iterations})"
        return { status: "iteration_cap", iterations: iterations - 1 }
      end

      result = step.call(context, harness: harness, returns: pending_returns)
      pending_returns = {}

      unless result[:ok]
        out.puts "until-empty: stopped, step refused (#{result[:reason]})"
        return { status: "refused", reason: result[:reason], iterations: iterations }
      end

      Array(result[:absorbed]).each { |a| out.puts "absorbed #{a[:node]}: #{a[:state]}" }

      case result[:status]
      when "complete"
        out.puts "complete"
        return { status: "complete", iterations: iterations }
      when "stalled"
        out.puts "stalled"
        Array(result[:blockers]).each { |b| out.puts "blocked: #{b}" }
        return { status: "stalled", iterations: iterations, blockers: result[:blockers] }
      when "needs_decision"
        stop = result[:stop]
        out.puts "needs_decision: #{stop[:node]} - #{stop[:question]}"
        out.puts stop[:answer_command]
        return { status: "needs_decision", iterations: iterations, stop: stop }
      end

      Array(result[:dispatched]).each do |node|
        next if active.key?(node)

        active[node] = node_run_spawner.call(context, node: node, harness: harness)
      end

      if active.empty?
        out.puts "stalled"
        out.puts "blocked: queued with no active node-run to wait on"
        return { status: "stalled", iterations: iterations,
                 blockers: ["queued with no active node-run to wait on"] }
      end

      finished = Array(node_run_waiter.call(active))
      finished.each do |f|
        active.delete(f[:node])
        out.puts "until-empty: index.lock collision recorded for #{f[:node]}" if index_lock_collision?(f)
        pending_returns[f[:node]] = f[:return_path]
      end
    end
  end

  # --- one turn ----------------------------------------------------------------

  # step_once(context, harness:, returns:) -> {ok:, reason:, status:,
  # dispatched: [node ids], stop:, blockers:, absorbed: [{node:, state:}]}.
  # Every absorb in `returns` runs in this one Ruby method, in the order
  # `returns` iterates, before `dispatch` ever runs (row 7.3) - never a
  # second call to this method from another thread while one is already in
  # flight (row 7.2), because #run above never starts a second one.
  def step_once(context, harness:, returns: {}, allow_core_drift: false, now: Time.now,
                sweep: RunnerSweep, absorb: RunnerAbsorb, dispatch: RunnerDispatch,
                worktree: NodeWorktree, lock: Lock, config_loader: method(:load_agent_config))
    abort_result = sweep.abort_if_merging(context)
    unless abort_result[:ok]
      return refusal("merge_in_progress", abort_result[:error])
    end

    lock.heartbeat(context.intent_dir, session: context.session) unless context.session.to_s.strip.empty?

    return refusal("lock_not_held", nil) unless context.session

    absorbed = returns.map do |node, path|
      result = absorb.absorb(context, node: node, return_path: path, allow_core_drift: allow_core_drift, now: now)
      { node: node, state: result[:state] }
    end

    swept = sweep.reclaim(context, skip: returns.keys, now: now)
    reaped = worktree.reap(context)

    agent_config = config_loader.call(context.plastic_home)
    dispatch_result = dispatch.dispatch(context, config: agent_config, harness: harness, now: now)
    unless dispatch_result[:ok]
      return refusal(dispatch_result[:reason], Array(dispatch_result[:errors]).join("; "))
    end

    {
      ok: true, reason: nil, status: dispatch_result[:status],
      dispatched: dispatch_result[:dispatched].map { |d| d[:node] },
      stop: dispatch_result[:stop], blockers: dispatch_result[:blockers], absorbed: absorbed,
      reclaimed: swept[:reclaimed], extended: swept[:extended], reaped: reaped[:removed],
    }
  end

  def refusal(reason, detail)
    { ok: false, reason: reason, detail: detail, status: nil, dispatched: [], stop: nil, blockers: [],
      absorbed: [] }
  end
  private_class_method :refusal

  # Mirrors scripts/runner's own Runner.load_agent_config exactly (row
  # 1.1 of nodes/n1.md): a missing or unparseable config.yml reads as {},
  # never raises, and it is read fresh every call rather than cached, since
  # a long-running until-empty process must see a config edit made mid-run
  # the same way a fresh `step` call always would.
  def load_agent_config(plastic_home)
    path = File.join(plastic_home.to_s, "config.yml")
    return {} unless File.exist?(path)

    YAML.safe_load(File.read(path)) || {}
  rescue StandardError
    {}
  end

  # --- node-run, the real subprocess --------------------------------------------

  # spawn_node_run(context, node:, harness:) -> a handle {node:, pid:,
  # stdout_io:, stderr_io:}. `harness:` is accepted for symmetry with
  # `step_once` even though node-run itself never takes a --harness flag -
  # the harness was already recorded on the node's own `running` line by the
  # dispatch this call followed, and node-run reads its packet off that
  # line, never off this argv. RUBYOPT is cleared explicitly, the same
  # contract every other ruby-spawning site in this tree carries.
  def spawn_node_run(context, node:, harness: nil)
    argv = [RbConfig.ruby, NODE_RUN_SCRIPT, context.intent_dir, "--node", node]
    argv += ["--session", context.session] if context.session

    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    pid = Process.spawn({ "RUBYOPT" => nil }, *argv, out: out_w, err: err_w)
    out_w.close
    err_w.close
    { node: node, pid: pid, stdout_io: out_r, stderr_io: err_r }
  end

  # wait_for_node_run(active) -> [{node:, return_path:, stderr:}] for
  # whichever ONE handle in `active` finishes first (real concurrency
  # between two live node-run processes; this call itself blocks on
  # whichever exits first, never both at once). `active` is keyed by node,
  # so a caller never needs to search its own values by pid outside this
  # method.
  def wait_for_node_run(active)
    pid, = Process.waitpid2(-1)
    handle = active.values.find { |h| h[:pid] == pid }
    return [] unless handle

    [{ node: handle[:node], return_path: read_and_close(handle[:stdout_io]).to_s.strip,
       stderr: read_and_close(handle[:stderr_io]) }]
  rescue Errno::ECHILD
    []
  end

  def read_and_close(io)
    io.read
  rescue StandardError
    ""
  ensure
    begin
      io.close
    rescue StandardError
      nil
    end
  end
  private_class_method :read_and_close

  # index_lock_collision?(finished) -> true when either the node-run
  # subprocess's own stderr or the return body it wrote mentions
  # `index.lock` - the shared signature of a git ref/index lock collision
  # between two worktrees writing into one repository's `.git` at the same
  # time (row 7.4). Never used to change what the loop does next: the
  # finished node's return is absorbed exactly like any other, and the
  # kind's own retry cap is what recovers it.
  def index_lock_collision?(finished)
    parts = [finished[:stderr].to_s]
    path = finished[:return_path]
    parts << safe_read_file(path) if path && !path.empty?
    parts.join("\n").match?(/index\.lock/i)
  end

  def safe_read_file(path)
    File.exist?(path) ? File.read(path) : ""
  rescue StandardError
    ""
  end
  private_class_method :safe_read_file
end
