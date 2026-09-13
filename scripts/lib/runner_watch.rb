# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "digest"
require "time"
require "rbconfig"
require_relative "worktree"
require_relative "runner_core"
require_relative "runner_sweep"
require_relative "ready_set"
require_relative "node_ledger"
require_relative "savepoint"
require_relative "atomic_write"
require_relative "runner_until_empty"
require_relative "harness_adapter"
require_relative "meter_watch"

# RunnerWatch (intent 340a, G7b, n1): one tick over disk truth. The whole
# watch minus the CLI and the dispatch branch (340a n2). Composes the
# existing modules the way RunnerSweep and MeterWatch already do - the
# git runner, the clock and the sweep module are all injected, nothing
# reads ENV, nothing evals.
#
# Order, fixed by graph.md D2: take a non-blocking lock on
# `<intent_dir>/watch.lock` for the whole tick (a losing tick is `busy`,
# writes nothing); `RunnerSweep.abort_if_merging`; refuse the tick outright
# on a half-finished merge (row 1.3), writing nothing; `RunnerSweep.reclaim`
# (never `RunnerSweep.run`, D3: that method heartbeats the delivery lease,
# which would keep a dead lead's lock fresh forever); classify (D4);
# persist the snapshot and the record line only when `record:` holds.
module RunnerWatch
  module_function

  LOCK_FILENAME = "watch.lock"
  STATE_FILENAME = "watch.state"
  RECORD_FILENAME = "watch.record"

  # Classes that never dispatch (D8): a finished delivery re-running its own
  # graph on every tick is exactly the bug a timer must not have.
  FINISHED_CLASSES = %w[closed done_unreported].freeze

  # tick(context, record:, dispatch:, harness:, now:, runner:, sweep:,
  # until_empty:) -> {class:, blockers:, ready:, reclaimed:, dispatched:,
  # tick:, busy:}. `dispatch:` (327 Q6, D7, D8) only ever runs under an
  # explicit ask - never inferred from the class - and only when the lock is
  # held, the class is not finished, and the meter does not read `stop`.
  # `until_empty:` is `RunnerUntilEmpty` by default; a test can inject a
  # double so the whole dispatch path never spawns a real `node-run`
  # subprocess. `harness=` and `meter=` on the record line read `-` only
  # when `dispatch:` itself was never asked for (D5) - every other refusal
  # (an unheld lock, a finished class, a stopped meter) still consults and
  # records the meter, since the tick DID look, it just chose not to act.
  def tick(context, record: true, dispatch: false, harness: nil, now: Time.now,
           runner: Worktree::ShellRunner.new, sweep: RunnerSweep, until_empty: RunnerUntilEmpty)
    intent_dir = context.intent_dir.to_s
    lock_handle = acquire_lock(File.join(intent_dir, LOCK_FILENAME))
    return busy_result unless lock_handle

    begin
      abort_result = sweep.abort_if_merging(context, runner: runner)
      unless abort_result[:ok]
        return {
          class: "merge_in_progress", blockers: [abort_result[:error]], ready: [],
          reclaimed: [], dispatched: [], tick: nil, busy: false,
        }
      end

      reclaim_result = sweep.reclaim(context, runner: runner, skip: [], now: now)
      reclaimed_ids = Array(reclaim_result[:reclaimed]).map { |r| r[:node] }

      view = classify(context, runner: runner, now: now, intent_dir: intent_dir)

      lock_state = context.session ? "held" : "not_held"
      harness_field = "-"
      meter_state = "-"
      dispatched_ids = []

      if dispatch
        harness_field = blank?(harness) ? "-" : harness.to_s
        meter_state = read_meter_state(context)

        if context.session && !FINISHED_CLASSES.include?(view[:class]) && meter_state != "stop"
          dispatched_ids = run_until_empty_dispatch(context, harness: harness, until_empty: until_empty)
        end
      end

      if record
        Worktree.ensure_gitignored(context.plastic_home, STATE_FILENAME, runner: runner)
        write_snapshot(intent_dir, view[:snapshot])
        append_record(
          intent_dir, now: now, tick: view[:tick], klass: view[:class],
          reclaimed: reclaimed_ids, ready: view[:ready], dispatched: dispatched_ids,
          harness: harness_field, meter: meter_state, lock: lock_state
        )
      end

      {
        class: view[:class], blockers: view[:blockers], ready: view[:ready],
        reclaimed: reclaimed_ids, dispatched: dispatched_ids, tick: view[:tick], busy: false,
      }
    ensure
      release_lock(lock_handle)
    end
  end

  # install_timer(context, home:, harness_key:, installer:) -> the written
  # plist path. Graph.md D9: the Codex carrier is `runner watch
  # --install-timer`, and it reuses MeterWatch's own writer through
  # `label:`/`arguments:` rather than rendering plist XML here (row 3.5) - a
  # second writer is exactly the drift D9 rules out. The label carries the
  # intent id (row 3.4), so a second intent's timer never overwrites the
  # first's job; `--dispatch --harness codex` rides the arguments only when
  # `HarnessAdapter.unattended_start?` holds for the resolved harness (row
  # 3.3), the same predicate `run_watch` itself already gates `--dispatch`
  # on. `installer:` is `MeterWatch` by default so a test can inject a
  # double that never touches a real home.
  def install_timer(context, home:, harness_key:, installer: MeterWatch)
    runner_path = File.expand_path(File.join(__dir__, "..", "runner"))
    arguments = [RbConfig.ruby, runner_path, "watch", context.intent_dir.to_s]
    arguments += ["--dispatch", "--harness", "codex"] if HarnessAdapter.unattended_start?(harness_key)

    installer.install_timer(home: home, script_path: runner_path,
                             label: "com.plastic.delivery-watch.#{context.intent_id}", arguments: arguments)
  end

  # run_until_empty_dispatch(context, harness:, until_empty:) -> every node
  # id the loop dispatched (C30). `until_empty.run` gets `step:` wrapped
  # around `until_empty.step_once` so this method sees every turn's own
  # `:dispatched` ids, the same shape RunnerDispatch.dispatch returns
  # (graph.md D8); `until_empty.run` itself still owns spawning and waiting
  # on the real `node-run` subprocesses (never duplicated here).
  def run_until_empty_dispatch(context, harness:, until_empty:)
    dispatched_ids = []
    wrapped_step = lambda do |ctx, harness:, returns:|
      result = until_empty.step_once(ctx, harness: harness, returns: returns)
      dispatched_ids.concat(Array(result[:dispatched]))
      result
    end

    until_empty.run(context, harness: harness, step: wrapped_step)
    dispatched_ids
  end
  private_class_method :run_until_empty_dispatch

  # read_meter_state(context) -> "ok", "reduce", "stop", "resume", "stale"
  # (whatever MeterWatch's own tick last wrote), or "unavailable" for a
  # missing or unparseable file (D8) - read-only, at MeterWatch's own state
  # path under `context.plastic_home`, never through a MeterWatch instance
  # (that class computes a FRESH state from the rate-limit cache; this tick
  # only ever reads what it already wrote).
  def read_meter_state(context)
    path = File.join(context.plastic_home.to_s, ".cache", "meter-state.json")
    return "unavailable" unless File.file?(path)

    state = JSON.parse(File.read(path))["state"]
    blank?(state) ? "unavailable" : state.to_s
  rescue StandardError
    "unavailable"
  end
  private_class_method :read_meter_state

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end
  private_class_method :blank?

  # fingerprint(context, runner:) -> the SHA256 D4 defines: savepoint.md's
  # current content plus the intent branch head, so a commit that lands no
  # ledger line still counts as movement (row 1.13). Public so a caller (and
  # this file's own tests) can compute the exact value a tick would compute
  # without duplicating the hashing here.
  def fingerprint(context, runner: Worktree::ShellRunner.new)
    content = savepoint_content(context.intent_dir)
    Digest::SHA256.hexdigest("#{content}\x1f#{branch_head_sha(context, runner)}")
  end

  # --- the lock ----------------------------------------------------------------

  def acquire_lock(path)
    handle = File.open(path, File::CREAT | File::RDWR, 0o644)
    return handle if handle.flock(File::LOCK_EX | File::LOCK_NB)

    handle.close
    nil
  rescue SystemCallError
    nil
  end
  private_class_method :acquire_lock

  def release_lock(handle)
    return unless handle

    handle.flock(File::LOCK_UN)
  rescue SystemCallError
    nil
  ensure
    handle&.close
  end
  private_class_method :release_lock

  def busy_result
    { class: nil, blockers: [], ready: [], reclaimed: [], dispatched: [], tick: nil, busy: true }
  end
  private_class_method :busy_result

  # --- classification (D4), first match wins ------------------------------------

  def classify(context, runner:, now:, intent_dir:)
    content = savepoint_content(intent_dir)
    recorded_pairs = Savepoint.savepoint_recorded_pairs(intent_dir)
    previous = read_snapshot(intent_dir)
    tick_number = (previous ? previous[:tick] : 0) + 1

    if closed?(recorded_pairs)
      return settle("closed", blockers: [], ready_ids: [], previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, runner: runner, now: now)
    end

    unless context.graph[:ok]
      errors = Array(context.graph[:errors])
      errors = ["graph.md could not be parsed"] if errors.empty?
      return settle("stalled", blockers: errors, ready_ids: [], previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, runner: runner, now: now)
    end

    if RunnerCore.complete?(context)
      return settle("done_unreported", blockers: [], ready_ids: [], previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, runner: runner, now: now)
    end

    ready_ids = ReadySet.analyze(intent_dir, now: now)[:ranked_ready].map { |r| r[:id] }
    running = any_running?(content)

    if !running && ready_ids.empty?
      return settle("stalled", blockers: blocked_reasons(context), ready_ids: ready_ids, previous: previous,
                     tick_number: tick_number, quiet_ticks: 0, content: content, context: context, runner: runner,
                     now: now)
    end

    current_fingerprint = fingerprint(context, runner: runner)

    if previous.nil? || previous[:fingerprint] != current_fingerprint
      return settle("moving", blockers: [], ready_ids: ready_ids, previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, runner: runner, now: now,
                     fingerprint: current_fingerprint)
    end

    next_quiet_ticks = previous[:quiet_ticks] + 1
    if previous[:quiet_ticks] >= 1 && !unexpired_running_lease?(content, now)
      klass = "stalled"
      blockers = ["no observed movement for #{next_quiet_ticks} consecutive ticks and no unexpired running lease"]
    else
      klass = "quiet"
      blockers = []
    end

    settle(klass, blockers: blockers, ready_ids: ready_ids, previous: previous, tick_number: tick_number,
           quiet_ticks: next_quiet_ticks, content: content, context: context, runner: runner, now: now,
           fingerprint: current_fingerprint)
  end
  private_class_method :classify

  # Assembles the return view plus the snapshot that will be persisted, when
  # `record:` is honored by the caller. `fingerprint:` defaults to a fresh
  # computation so every class - not only moving/quiet/stalled-by-quiet -
  # persists a value later ticks can compare against.
  def settle(klass, blockers:, ready_ids:, previous:, tick_number:, quiet_ticks:, content:, context:, runner:,
             now:, fingerprint: nil)
    fp = fingerprint || RunnerWatch.fingerprint(context, runner: runner)
    {
      class: klass, blockers: blockers, ready: ready_ids, tick: tick_number,
      snapshot: { fingerprint: fp, quiet_ticks: quiet_ticks, tick: tick_number, at: now.utc.iso8601 },
    }
  end
  private_class_method :settle

  def closed?(recorded_pairs)
    recorded_pairs.include?(["Done", "delivered"]) || recorded_pairs.include?(["Done", "abandoned"])
  end
  private_class_method :closed?

  def blocked_reasons(context)
    rows = RunnerCore.status(context)
    rows.values.reject { |v| ReadySet::TERMINAL_STATES.include?(v[:state]) || v[:ready] }
        .flat_map { |v| v[:blockers] }
        .uniq
  end
  private_class_method :blocked_reasons

  def any_running?(content)
    NodeLedger.status_from_content(content).value?("running")
  end
  private_class_method :any_running?

  def unexpired_running_lease?(content, now)
    status_map = NodeLedger.status_from_content(content)
    entries = NodeLedger.entries_from_content(content)
    status_map.any? do |subject, state|
      next false unless state == "running"

      last = entries.select { |e| !e[:torn] && e[:subject] == subject && e[:state] == "running" }.last
      next false unless last

      at = parse_time((last[:fields] || {})["expires"])
      at && now < at
    end
  end
  private_class_method :unexpired_running_lease?

  def branch_head_sha(context, runner)
    worktree = context.worktree
    return "" if worktree.nil? || worktree.to_s.strip.empty?

    res = runner.run("-C", worktree, "rev-parse", "HEAD")
    res.success? ? res.stdout.to_s.strip : ""
  rescue StandardError
    ""
  end
  private_class_method :branch_head_sha

  def parse_time(raw)
    return nil if raw.nil? || raw.to_s.strip.empty?

    Time.iso8601(raw.to_s)
  rescue ArgumentError
    nil
  end
  private_class_method :parse_time

  def savepoint_content(intent_dir)
    path = File.join(intent_dir.to_s, "savepoint.md")
    File.exist?(path) ? File.read(path) : ""
  end
  private_class_method :savepoint_content

  # --- the snapshot (D5) ---------------------------------------------------------

  def read_snapshot(intent_dir)
    path = File.join(intent_dir, STATE_FILENAME)
    return nil unless File.file?(path)

    data = JSON.parse(File.read(path))
    { fingerprint: data["fingerprint"], quiet_ticks: data["quiet_ticks"].to_i, tick: data["tick"].to_i,
      at: data["at"] }
  rescue StandardError
    nil
  end
  private_class_method :read_snapshot

  def write_snapshot(intent_dir, snapshot)
    path = File.join(intent_dir, STATE_FILENAME)
    data = {
      "fingerprint" => snapshot[:fingerprint], "quiet_ticks" => snapshot[:quiet_ticks],
      "tick" => snapshot[:tick], "at" => snapshot[:at],
    }
    AtomicWrite.write(path, JSON.generate(data))
  end
  private_class_method :write_snapshot

  # --- the record (D5) -----------------------------------------------------------

  def append_record(intent_dir, now:, tick:, klass:, reclaimed:, ready:, dispatched:, harness: "-", meter: "-",
                     lock:)
    line = "#{now.utc.iso8601}  tick=#{tick} class=#{klass} reclaimed=#{list_or_dash(reclaimed)} " \
           "ready=#{list_or_dash(ready)} dispatched=#{list_or_dash(dispatched)} harness=#{harness} " \
           "meter=#{meter} lock=#{lock}\n"
    File.open(File.join(intent_dir, RECORD_FILENAME), "a") { |f| f.write(line) }
  end
  private_class_method :append_record

  def list_or_dash(list)
    list.nil? || list.empty? ? "-" : list.join(",")
  end
  private_class_method :list_or_dash
end
