# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "digest"
require "time"
require_relative "worktree"
require_relative "runner_core"
require_relative "runner_sweep"
require_relative "ready_set"
require_relative "node_ledger"
require_relative "savepoint"
require_relative "atomic_write"

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

  # tick(context, record:, dispatch:, now:, runner:, sweep:) -> {class:,
  # blockers:, ready:, reclaimed:, dispatched:, tick:, busy:}. `dispatch:` is
  # accepted and ignored here; 340a n2 fills it in. `dispatched` always
  # reads `[]` and the record line's `dispatched=`, `harness=` and `meter=`
  # fields always read `-` until then.
  def tick(context, record: true, dispatch: false, now: Time.now,
           runner: Worktree::ShellRunner.new, sweep: RunnerSweep)
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

      if record
        Worktree.ensure_gitignored(context.plastic_home, STATE_FILENAME, runner: runner)
        write_snapshot(intent_dir, view[:snapshot])
        append_record(
          intent_dir, now: now, tick: view[:tick], klass: view[:class],
          reclaimed: reclaimed_ids, ready: view[:ready], dispatched: []
        )
      end

      {
        class: view[:class], blockers: view[:blockers], ready: view[:ready],
        reclaimed: reclaimed_ids, dispatched: [], tick: view[:tick], busy: false,
      }
    ensure
      release_lock(lock_handle)
    end
  end

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

  def append_record(intent_dir, now:, tick:, klass:, reclaimed:, ready:, dispatched:)
    line = "#{now.utc.iso8601}  tick=#{tick} class=#{klass} reclaimed=#{list_or_dash(reclaimed)} " \
           "ready=#{list_or_dash(ready)} dispatched=#{list_or_dash(dispatched)} harness=- meter=- lock=held\n"
    File.open(File.join(intent_dir, RECORD_FILENAME), "a") { |f| f.write(line) }
  end
  private_class_method :append_record

  def list_or_dash(list)
    list.nil? || list.empty? ? "-" : list.join(",")
  end
  private_class_method :list_or_dash
end
