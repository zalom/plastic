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
require_relative "meter_watch"

# RunnerWatch (intent 340a, G7b, n1): one tick over disk truth. The whole
# watch minus the CLI (340a n2). It never dispatches (intent 391). Composes the
# existing modules the way RunnerSweep and MeterWatch already do - the clock
# and the sweep module are all injected, nothing reads ENV, nothing evals,
# and no method here runs a version control command (owner ruling
# 2026-09-24).
#
# Order, fixed by graph.md D2: take a non-blocking lock on
# `<intent_dir>/watch.lock` for the whole tick (a losing tick is `busy`,
# writes nothing); `RunnerSweep.reclaim` (never `RunnerSweep.run`, D3: that
# method heartbeats the delivery lease, which would keep a dead lead's lock
# fresh forever); classify (D4); persist the snapshot and the record line
# only when `record:` holds. Owner ruling 2026-09-24: the
# `RunnerSweep.abort_if_merging` step this tick once ran before reclaim is
# gone - Plastic runs no merge of its own to leave half-finished, so there is
# nothing left to abort on.
module RunnerWatch
  module_function

  LOCK_FILENAME = "watch.lock"
  STATE_FILENAME = "watch.state"
  RECORD_FILENAME = "watch.record"

  # tick(context, record:, now:, sweep:) -> {class:, blockers:, ready:,
  # reclaimed:, tick:, busy:}.
  def tick(context, record: true, now: Time.now, sweep: RunnerSweep)
    intent_dir = context.intent_dir.to_s
    lock_handle = acquire_lock(File.join(intent_dir, LOCK_FILENAME))
    return busy_result unless lock_handle

    begin
      reclaim_result = sweep.reclaim(context, skip: [], now: now)
      reclaimed_ids = Array(reclaim_result[:reclaimed]).map { |r| r[:node] }
      extended = !Array(reclaim_result[:extended]).empty?

      view = classify(context, now: now, intent_dir: intent_dir, extended: extended)

      if record
        Worktree.ensure_gitignored(context.plastic_home, STATE_FILENAME)
        write_snapshot(intent_dir, view[:snapshot])
        append_record(
          intent_dir, now: now, tick: view[:tick], klass: view[:class],
          reclaimed: reclaimed_ids, ready: view[:ready], lock: context.session ? "held" : "not_held"
        )
      end

      {
        class: view[:class], blockers: view[:blockers], ready: view[:ready],
        reclaimed: reclaimed_ids, tick: view[:tick], busy: false,
      }
    ensure
      release_lock(lock_handle)
    end
  end

  # install_timer(context, home:, installer:) -> the written plist path.
  # Graph.md D9: the Codex carrier is `runner watch --install-timer`, and it
  # reuses MeterWatch's own writer through `label:`/`arguments:` rather than
  # rendering plist XML here (row 3.5) - a second writer is exactly the drift
  # D9 rules out. The label carries the intent id (row 3.4), so a second
  # intent's timer never overwrites the first's job. `installer:` is
  # `MeterWatch` by default so a test can inject a double that never touches
  # a real home.
  def install_timer(context, home:, installer: MeterWatch)
    runner_path = File.expand_path(File.join(__dir__, "..", "runner"))
    arguments = [RbConfig.ruby, runner_path, "watch", context.intent_dir.to_s]

    installer.install_timer(home: home, script_path: runner_path,
                             label: "com.plastic.delivery-watch.#{context.intent_id}", arguments: arguments)
  end

  # fingerprint(context) -> the SHA256 D4 defines: savepoint.md's current
  # content plus the intent worktree's own newest file mtime (see
  # `worktree_signal`), so a file change that lands no ledger line still
  # counts as movement (row 1.13). Public so a caller (and this file's own
  # tests) can compute the exact value a tick would compute without
  # duplicating the hashing here.
  def fingerprint(context)
    content = savepoint_content(context.intent_dir)
    Digest::SHA256.hexdigest("#{content}\x1f#{worktree_signal(context)}")
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
    { class: nil, blockers: [], ready: [], reclaimed: [], tick: nil, busy: true }
  end
  private_class_method :busy_result

  # --- classification (D4), first match wins ------------------------------------

  def classify(context, now:, intent_dir:, extended: false)
    content = savepoint_content(intent_dir)
    recorded_pairs = Savepoint.savepoint_recorded_pairs(intent_dir)
    previous = read_snapshot(intent_dir)
    tick_number = (previous ? previous[:tick] : 0) + 1

    if closed?(recorded_pairs)
      return settle("closed", blockers: [], ready_ids: [], previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, now: now)
    end

    unless context.graph[:ok]
      errors = Array(context.graph[:errors])
      errors = ["graph.md could not be parsed"] if errors.empty?
      return settle("stalled", blockers: errors, ready_ids: [], previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, now: now)
    end

    if RunnerCore.complete?(context)
      return settle("done_unreported", blockers: [], ready_ids: [], previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, now: now)
    end

    ready_ids = ReadySet.analyze(intent_dir, now: now)[:ranked_ready].map { |r| r[:id] }
    running = any_running?(content)

    if !running && ready_ids.empty?
      return settle("stalled", blockers: blocked_reasons(context), ready_ids: ready_ids, previous: previous,
                     tick_number: tick_number, quiet_ticks: 0, content: content, context: context,
                     now: now)
    end

    current_fingerprint = fingerprint(context)

    # B2: a reclaim that extended a lease is evidence of live work (the
    # sweep extends only when the node branch has commits newer than the
    # expiry), so it counts as movement here, at the fingerprint
    # comparison, after closed/malformed-graph/done_unreported/the
    # nothing-running-nothing-ready stall have already returned above.
    if extended || previous.nil? || previous[:fingerprint] != current_fingerprint
      return settle("moving", blockers: [], ready_ids: ready_ids, previous: previous, tick_number: tick_number,
                     quiet_ticks: 0, content: content, context: context, now: now,
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
           quiet_ticks: next_quiet_ticks, content: content, context: context, now: now,
           fingerprint: current_fingerprint)
  end
  private_class_method :classify

  # Assembles the return view plus the snapshot that will be persisted, when
  # `record:` is honored by the caller. `fingerprint:` defaults to a fresh
  # computation so every class - not only moving/quiet/stalled-by-quiet -
  # persists a value later ticks can compare against.
  def settle(klass, blockers:, ready_ids:, previous:, tick_number:, quiet_ticks:, content:, context:,
             now:, fingerprint: nil)
    fp = fingerprint || RunnerWatch.fingerprint(context)
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

  # The newest mtime among every file under the intent worktree, or "" when
  # there is no worktree or it is empty - the file-system replacement for
  # the git branch head sha this used to hash (owner ruling 2026-09-24:
  # Plastic reads no git history), so a file a node writes without landing a
  # ledger line still counts as movement (row 1.13).
  def worktree_signal(context)
    worktree = context.worktree
    return "" if worktree.nil? || worktree.to_s.strip.empty? || !Dir.exist?(worktree)

    newest = Dir.glob(File.join(worktree, "**", "*"), File::FNM_DOTMATCH)
                .reject { |f| File.directory?(f) }
                .map { |f| File.mtime(f) }
                .max
    newest ? newest.utc.iso8601 : ""
  rescue StandardError
    ""
  end
  private_class_method :worktree_signal

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

  def append_record(intent_dir, now:, tick:, klass:, reclaimed:, ready:, lock:)
    line = "#{now.utc.iso8601}  tick=#{tick} class=#{klass} reclaimed=#{list_or_dash(reclaimed)} " \
           "ready=#{list_or_dash(ready)} lock=#{lock}\n"
    File.open(File.join(intent_dir, RECORD_FILENAME), "a") { |f| f.write(line) }
  end
  private_class_method :append_record

  def list_or_dash(list)
    list.nil? || list.empty? ? "-" : list.join(",")
  end
  private_class_method :list_or_dash
end
