#!/usr/bin/env ruby
# encoding: UTF-8

require "json"
require "yaml"
require "fileutils"
require "tempfile"
require "digest"
require "socket"
require_relative "worktree"
require_relative "db"

module Bridge
  STAGES = %w[what why how exec done].freeze

  # Placeholder sentinel (intent 60b). A scaffolded lifecycle file
  # (spec.md/plan.md/checklist.md/outcome.md) carries this exact string as its
  # first line until an agent fills the file and deletes the sentinel. The
  # sentinel is the "stage not reached yet" marker, so stage detection treats a
  # sentinel-marked file as absent (see stage_file_present?). The intent file
  # (<id>--<slug>.md) is never sentineled; it is born complete.
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"

  # Bridge cleanup is terminal-state, not age-based (intent 80). A bridge is dead
  # weight ONLY once its intent is terminal (no longer in its store's INDEX.md
  # `## Active` block); such bridges are purged. An Active intent's bridge is kept
  # unconditionally, because while the intent is live the bridge is still load-
  # bearing: it is the continuation signal (a parked or interrupted run resumes
  # from it) and the anti-collision lock (it keys the per-session statusline so
  # parallel sessions do not overwrite each other). An age window was the wrong
  # axis: it left dead bridges resident for ~2 days AND could reap bridges of
  # interrupted-but-still-active intents, which are exactly the ones to preserve.

  def self.intent_file(intent_dir)
    dir_name = File.basename(intent_dir)
    "#{intent_dir}/#{dir_name}.md"
  end

  # Store-home resolution for the sessions/lock_leases/savepoint_events tables
  # (intent 41 cutover, replacing the /tmp bridge dir). ENV["PLASTIC_STORE_HOME"]
  # is the hermetic test seam (mirrors the retired PLASTIC_TMP): when set, it
  # wins outright and no cwd/projects.yml lookup happens at all. The production
  # default is the unchanged AC6 CWD-match/global-on-miss resolver.
  def self.resolve_store_home(cwd: Dir.pwd)
    override = ENV["PLASTIC_STORE_HOME"]
    return override unless blank?(override)
    Plastic::DB::StoreResolver.resolve(cwd: cwd)[:store_home]
  end

  # The sessions.session_id key a bare `session` uses for `intent_id` (intent
  # 131 convention, preserved across the cutover): a per-intent key, since a
  # bare session can legitimately own several concurrently-armed intents and
  # sessions.session_id is UNIQUE (one row per key).
  def self.session_key(session, intent_id)
    "#{session}--#{intent_id}"
  end

  # --- Session resolution (intent 52) ----------------------------------------

  def self.blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # Raised by arm when the delivery lock cannot be acquired (held elsewhere,
  # stale, excluded, or corrupt). The message names the resolving command.
  class LockHeldError < StandardError; end

  # The absolute intent dir a bridge points at, or nil.
  def self.bridge_intent_dir(bridge_data)
    return nil unless bridge_data.is_a?(Hash)
    info = bridge_data["intent"] || {}
    store = info["store"]
    dir = info["dir"]
    (store && dir) ? File.expand_path("#{store}/#{dir}") : nil
  end

  # Bridge-cache copy of the delivery lease's fields (D2: the bridge is a
  # CACHE; the lease row is the truth). Never carries a pid. `row` is a
  # lock_leases row Hash (owner_session/host/acquired_at/artifact/id); nil
  # yields the empty cache shape.
  def self.lock_cache_from_lease(store_home, row)
    if row.nil?
      return { "owner_session" => nil, "acquired_at" => nil, "host" => nil,
               "type" => nil, "delegates" => [] }
    end

    conn = Plastic::DB.connect(store_home)
    delegates = conn ? Plastic::DB::Leases.delegates_for(conn, row["id"]) : []
    {
      "owner_session" => row["owner_session"],
      "acquired_at" => row["acquired_at"],
      "host" => row["host"],
      "type" => blank?(row["artifact"]) ? "delivery" : "artifact",
      "delegates" => delegates,
    }
  end

  # Deterministic, session-id-less bridge key derived from store + intent id.
  # Stable across processes so a session-less arm and a later session-less
  # gate-check resolve to the same bridge file.
  def self.derive_key(store, intent_id)
    "auto-" + Digest::SHA256.hexdigest("#{store}/#{intent_id}")[0, 10]
  end

  # Resolve a bridge session: first non-empty of explicit (the stdin session_id),
  # CLAUDE_CODE_SESSION_ID, then a derived key. Never returns nil/empty.
  # Whitespace-only counts as empty.
  #
  # The CLAUDE_CODE_SESSION_ID fallback (intent 79) carries the bg/headless real
  # session id (Claude Code passes session_id on stdin, not via an env var; the
  # headless id lives in CLAUDE_CODE_SESSION_ID). Keying by the real id (instead of
  # a derived hash) lets the statusline, which receives that same id on stdin, find
  # the bridge by direct filename lookup.
  def self.resolve_session(explicit, intent_id:, store:)
    return explicit.to_s.strip unless blank?(explicit)
    code_env = ENV["CLAUDE_CODE_SESSION_ID"]
    return code_env.to_s.strip unless blank?(code_env)
    derive_key(store, intent_id)
  end

  # Walk up from file_path; return the first ancestor that looks like an intent
  # directory (`.../store/<id>--<slug>`), else nil. Used to derive the savepoint
  # target without needing a bridge. The input is always a file inside the intent
  # dir (never the dir itself), so the walk-up starts at its parent.
  def self.intent_dir_for(file_path)
    dir = File.expand_path(file_path)
    loop do
      parent = File.dirname(dir)
      break if parent == dir # reached filesystem root
      dir = parent
      return dir if dir.match?(%r{/store/[^/]+--[^/]+\z})
    end
    nil
  end

  # A bridge hash is usable iff it has a non-empty session and an intent Hash.
  def self.bridge_valid?(data)
    data.is_a?(Hash) && !blank?(data["session"]) && data["intent"].is_a?(Hash)
  end

  # Resolve the active bridge from the `sessions` table (intent 41 cutover,
  # replacing the /tmp bridge scan). Opens the caller's store (ENV
  # PLASTIC_STORE_HOME override, else CWD-match/global-on-miss, AC6 unchanged),
  # lets Sessions.active_for pick the row (strict per-session ownership, then
  # cwd tiering, then auto-preference, then newest last_seen_at -- intent
  # 90/131 parity, ported to the DB layer in ACTION_4), resolves that row's
  # intent dir, and adapts it into the SAME Hash shape the retired /tmp bridge
  # produced (Sessions.to_bridge_data) so the gate-decision functions read it
  # unchanged.
  #
  # A stale /tmp/plastic-*.json is NEVER read here (AC7 /tmp half): the
  # sessions table is the only source. Fails open (nil) when the DB is
  # unavailable, the store has no matching session row, or the row's intent
  # dir cannot be found on disk -- exactly like "no bridge" did before.
  def self.discover_bridge(session:, cwd: Dir.pwd, store_home: nil)
    home = store_home || resolve_store_home(cwd: cwd)
    conn = Plastic::DB.connect(home)
    return nil if conn.nil?

    row = Plastic::DB::Sessions.active_for(conn, session: session, cwd: cwd)
    return nil if row.nil?

    intent_id = row["active_intent_id"]
    return nil if blank?(intent_id)
    intent_dir = Dir.glob(File.join(home, "store", "#{intent_id}--*")).first
    return nil if intent_dir.nil?

    lock_row = Plastic::DB::Sessions.current_lock_row(conn, intent_id)
    Plastic::DB::Sessions.to_bridge_data(row, intent_dir: intent_dir, lock_row: lock_row)
  rescue StandardError
    nil
  end

  # --- Terminal-state bridge purge (intent 80) -------------------------------

  # True iff the intent is Active in its store's INDEX.md. An INDEX.md lives at
  # the PARENT of the store/ dir the bridge records, so we resolve it from the
  # bridge's intent.store. Non-raising: any failure (missing/unreadable INDEX,
  # bad arg) returns false, which means "not active" so the caller treats the
  # bridge as purgeable. `index_active_ids` is a pure-data test seam: when an
  # Array of id strings is supplied, membership is checked against it directly
  # with no file read.
  def self.intent_active?(intent_id, store:, index_active_ids: nil)
    target = intent_id.to_s
    return index_active_ids.include?(target) if index_active_ids.is_a?(Array)

    index = File.join(File.dirname(store.to_s), "INDEX.md")
    return false unless File.exist?(index)

    in_active = false
    File.foreach(index) do |line|
      stripped = line.chomp
      if stripped == "## Active"
        in_active = true
        next
      end
      next unless in_active
      break if stripped.start_with?("## ") # next section ends the Active block
      m = stripped.match(/^- \[(\S+) +—/)
      return true if m && m[1] == target
    end
    false
  rescue StandardError
    false
  end

  # Session GC (intent 41 cutover; was purge_done_bridges over /tmp files).
  # Ends (deletes) every OTHER session row in `store`'s DB whose active intent
  # is terminal (not in its store's INDEX.md `## Active` block -- the
  # unchanged intent_active? read; 147 owns the INDEX-read cutover, not this
  # one). `session` is the CALLER's BARE session id (intent 131): a session
  # legitimately owns SEVERAL per-intent rows (one per concurrent intent), so
  # every row in that whole family (bare key or `"#{session}--<intent_id>"`)
  # is protected, never just one exact row -- mirroring the old own-prefix
  # skip over /tmp files. Also never ends a row whose intent still holds a
  # live delivery lock (D6): the End tail clears the lock BEFORE a session
  # becomes GC-eligible. Best-effort and non-raising; returns the Array of
  # ended session_ids.
  def self.purge_done_bridges(session:, store:)
    store_home = File.dirname(store)
    conn = Plastic::DB.connect(store_home)
    return [] if conn.nil?

    removed = []
    Plastic::DB::Sessions.all(conn).each do |row|
      sid = row["session_id"].to_s
      next if sid == session.to_s || sid.start_with?("#{session}--")
      id = row["active_intent_id"]
      # A blank active_intent_id is junk (mirrors the old "missing intent.id"
      # bridge purge): it can never be kept, since there is nothing to check
      # liveness against.
      keep = !blank?(id) && intent_active?(id, store: store)
      keep ||= !blank?(id) && Plastic::DB::Leases.current(conn, id) != nil
      next if keep

      Plastic::DB::Sessions.end(conn, session_id: row["session_id"])
      removed << row["session_id"]
    end
    removed
  rescue => e
    $stderr.puts "plastic: purge_done_bridges failed: #{e.message}"
    []
  end

  # True iff a lifecycle file is PRESENT AND REAL: it exists and its first line is
  # not the placeholder sentinel. Reads only the file head (never the whole file)
  # so the dashboard stays fast across many intents. Exact first-line match only,
  # so a real file that merely contains an HTML comment later is unaffected, and a
  # partially-edited sentinel reads as real rather than sticking as a placeholder.
  def self.stage_file_present?(path)
    return false unless File.exist?(path)
    first = File.open(path, &:gets)
    return true if first.nil? # empty file: present, not a sentinel
    first.chomp != PLACEHOLDER_SENTINEL
  rescue StandardError
    File.exist?(path)
  end

  def self.derive_stage(intent_dir)
    return "done" if stage_file_present?("#{intent_dir}/outcome.md")
    if stage_file_present?("#{intent_dir}/plan.md") &&
       File.directory?("#{intent_dir}/actions") &&
       stage_file_present?("#{intent_dir}/checklist.md")
      return "exec"
    end
    return "how" if stage_file_present?("#{intent_dir}/spec.md")
    return "why" if File.exist?(intent_file(intent_dir))
    "what"
  end

  def self.has_files(intent_dir)
    files = []
    ifile = File.basename(intent_file(intent_dir))
    files << ifile if File.exist?("#{intent_dir}/#{ifile}")
    ["spec.md", "plan.md", "checklist.md", "outcome.md"].each do |f|
      files << f if stage_file_present?("#{intent_dir}/#{f}")
    end
    files << "actions/" if File.directory?("#{intent_dir}/actions")
    files
  end

  def self.missing_for_stage(stage, intent_dir = nil)
    ifile = intent_dir ? File.basename(intent_file(intent_dir)) : "intent.md"
    case stage
    when "what" then [ifile]
    when "why" then ["spec.md"]
    when "how" then ["plan.md", "actions/", "checklist.md"]
    when "exec" then ["outcome.md"]
    else []
    end
  end

  # --- Gate-boundary narration (intent 84, Lever 1) -------------------------
  #
  # ONE concise sentence that states what happened AND what's next, preserving
  # the `Next: ...` hint the agent consumes. Pure and side-effect-free so the
  # hook stays a thin caller and the formatter is unit-testable in isolation.
  # No "Stage transition: X -> Y" prose, no arrow; a colon/parentheses carry the
  # stage word. Returns a single line (no embedded newlines).
  STAGE_LABELS = {
    "what" => "What", "why" => "Why", "how" => "How",
    "exec" => "Exec", "done" => "Done"
  }.freeze

  NEXT_HINTS = {
    "why" => "write spec.md",
    "how" => "Why complete. Invoke plastic-auto to deliver autonomously, or write plan.md manually.",
    "exec" => "How complete. Invoke plastic-auto or plastic-executing-plan to execute, or work through the checklist manually.",
    "done" => "Exec complete. Intent must be completed now — write outcome.md, update INDEX.md, auto-commit. Use plastic-auto or do it manually."
  }.freeze

  def self.stage_label(stage)
    STAGE_LABELS[stage] || stage.to_s
  end

  # Build the gate-hook `additionalContext` sentence.
  #   transition:      "PLASTIC: How reached (plan.md written). Next: <hint>"
  #   same-stage write: "PLASTIC: plan.md written (How). Next: <hint>"
  # `new_missing` (missing files for the new stage) takes precedence over the
  # stage hint, exactly as before, so the `Next:` content is unchanged.
  def self.gate_narration(old_stage:, new_stage:, basename:, new_missing:, next_hints: NEXT_HINTS)
    head = if old_stage != new_stage
             "PLASTIC: #{stage_label(new_stage)} reached (#{basename} written)."
           else
             "PLASTIC: #{basename} written (#{stage_label(new_stage)})."
           end

    nxt =
      if Array(new_missing).any?
        "Next: #{Array(new_missing).join(", ")}"
      elsif next_hints[new_stage]
        "Next: #{next_hints[new_stage]}"
      end

    nxt ? "#{head} #{nxt}" : head
  end

  # --- Cycle-step savepoint ledger (intent 34) ------------------------------
  #
  # savepoint.md is a deterministic, append-only, one-line-per-milestone ledger
  # (newest at the bottom). It is sugar on top of the conventions: derived from
  # files-on-disk, rebuildable, never a source of truth. Milestones are
  # file-event boundaries only; action/resource files record nothing.

  SAVEPOINT_FILE = "savepoint.md"

  # Map a written filename to [stage_label, milestone_text], or nil if the file
  # is not a lifecycle milestone.
  def self.savepoint_milestone(intent_dir, basename)
    return ["What", basename] if basename == File.basename(intent_file(intent_dir))

    case basename
    when "spec.md"      then ["Why", "spec.md created"]
    when "plan.md"      then ["How", "plan.md created"]
    when "checklist.md" then ["How", "checklist.md created"]
    when "outcome.md"   then ["Exec", "outcome.md created"]
    end
  end

  # Milestones already recorded in the ledger (field 3 of each line).
  def self.savepoint_recorded_milestones(intent_dir)
    f = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(f)
    File.read(f).each_line.map do |line|
      parts = line.strip.split(/\s{2,}/)
      parts.length >= 3 ? parts[2] : nil
    end.compact
  end

  # (stage, milestone) pairs already recorded in the ledger. The pair (not the
  # milestone text alone) is the dedup key, because state-from-ledger lines like
  # `Why  started` and `How  started` share the milestone text "started" while
  # being distinct events (intent 81).
  def self.savepoint_recorded_pairs(intent_dir)
    f = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(f)
    File.read(f).each_line.filter_map do |line|
      parts = line.strip.split(/\s{2,}/)
      parts.length >= 3 ? [parts[1], parts[2]] : nil
    end
  end

  # Append one ledger line for (stage, milestone) unless that pair is already
  # recorded. The single append primitive shared by every line class. Returns
  # true when a line was written, false when it was a no-op.
  def self.append_savepoint_line(intent_dir, stage, milestone, now)
    return false if savepoint_recorded_pairs(intent_dir).include?([stage, milestone])
    line = "#{now.utc.iso8601}  #{stage}  #{milestone}\n"
    File.open(File.join(intent_dir, SAVEPOINT_FILE), "a") { |io| io.write(line) }
    true
  end

  # Append the artifact-landing milestone for file_path if (and only if) it is a
  # milestone not already recorded. Returns true when a line was written.
  def self.append_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_milestone(intent_dir, basename)
    return false unless milestone
    # A sentinel-marked lifecycle file logs NO milestone (the stage is not real
    # yet). The intent file is never sentineled, so it still logs its What line.
    return false unless stage_file_present?(File.join(intent_dir, basename))

    append_savepoint_line(intent_dir, stage, milestone, now)
  end

  # --- State-from-ledger: pre-stage, exec-start, and terminal lines (81) ------
  #
  # On top of intent 34's artifact-landing milestones, the ledger gains:
  #   - `started` lines, one per cycle stage entry (pre-stage, written by the
  #     PreToolUse savepoint hook the moment a stage's artifact is first written);
  #   - an `Exec  started` companion emitted when checklist.md lands;
  #   - a terminal `Done  delivered|abandoned` line written by the completion path.
  # None of these are derivable from files on disk, so they are deliberately NOT
  # part of savepoint_milestone and are never regenerated by rebuild_savepoint:
  # a rebuilt ledger is the file-landing skeleton, the live ledger is richer.

  # Map a written filename to the [stage, "started"] pre-stage milestone, or nil.
  # spec.md => entering Why, plan.md => entering How. checklist.md/outcome.md do
  # not open a stage (checklist's Exec-start is the append_exec_started companion).
  def self.savepoint_started_milestone(basename)
    case basename
    when "spec.md" then ["Why", "started"]
    when "plan.md" then ["How", "started"]
    end
  end

  # Append the pre-stage `started` line for file_path, iff: the basename opens a
  # stage, the stage is genuinely starting (its artifact is not yet a REAL file,
  # so a sentinel placeholder still counts as "starting"), and the pair is not
  # already recorded. Returns true when a line was written.
  def self.append_started_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_started_milestone(basename)
    return false unless milestone
    return false if stage_file_present?(File.join(intent_dir, basename))

    append_savepoint_line(intent_dir, stage, milestone, now)
  end

  # Append the `Exec  started` companion (emitted when checklist.md lands, in the
  # same PostToolUse event as the `How  checklist.md created` line). Idempotent.
  def self.append_exec_started(intent_dir, now: Time.now)
    append_savepoint_line(intent_dir, "Exec", "started", now)
  end

  TERMINAL_DISPOSITIONS = %w[delivered abandoned].freeze

  # Append the terminal bookend `Done  delivered|abandoned`, written by the
  # completion path when an intent transfers to INDEX's Completed/Abandoned
  # section. Idempotent per disposition. Raises on an unknown disposition.
  def self.append_terminal_savepoint(intent_dir, disposition, now: Time.now)
    unless TERMINAL_DISPOSITIONS.include?(disposition)
      raise ArgumentError,
            "disposition must be one of #{TERMINAL_DISPOSITIONS.join(', ')}, got #{disposition.inspect}"
    end

    append_savepoint_line(intent_dir, "Done", disposition, now)
  end

  # --- Tier convenience line (intent 130, D-A) ------------------------------
  #
  # spec.md's top `Tier: S|M|L` line is the single authoritative record of an
  # intent's proportional-auto-sizing tier (see PLASTIC.md `## Tiers`). This
  # reads that line only; it never validates or enforces it (convention-only,
  # matching the skill and agent contracts). Returns nil when spec.md is
  # absent, empty, or its first line does not match, so a missing/malformed
  # Tier line changes nothing about existing rebuild behavior.
  def self.savepoint_tier(intent_dir)
    path = File.join(intent_dir, "spec.md")
    return nil unless File.exist?(path)
    first = File.open(path, &:gets)
    return nil if first.nil?
    m = first.chomp.strip.match(/\ATier:\s*(S|M|L)\z/)
    m && m[1]
  end

  # Reconstruct the ledger from files on disk (timestamps from mtimes), in
  # stage order, overwriting savepoint.md. Returns the number of lines written.
  # When spec.md carries a Tier line, one convenience `Tier  <value>` line is
  # echoed right after the spec.md milestone line (same mtime), so the tier
  # survives a rebuild without becoming a new source of truth.
  def self.rebuild_savepoint(intent_dir)
    ordered = [
      File.basename(intent_file(intent_dir)),
      "spec.md", "plan.md", "checklist.md", "outcome.md",
    ]
    lines = ordered.flat_map do |basename|
      path = File.join(intent_dir, basename)
      next [] unless stage_file_present?(path)
      stage, milestone = savepoint_milestone(intent_dir, basename)
      next [] unless milestone
      stamp = File.mtime(path).utc.iso8601
      entry = "#{stamp}  #{stage}  #{milestone}\n"
      if basename == "spec.md" && (tier = savepoint_tier(intent_dir))
        [entry, "#{stamp}  Tier  #{tier}\n"]
      else
        [entry]
      end
    end
    File.write(File.join(intent_dir, SAVEPOINT_FILE), lines.join)
    lines.length
  end

  # Compute AND persist the current session/intent state (intent 41 cutover,
  # replacing the /tmp bridge write). The returned Hash is the SAME bridge_data
  # shape the retired /tmp bridge produced, built directly here (not via a DB
  # round-trip) so a caller still gets a usable Hash back even when the DB is
  # unavailable (fail open, always); the sessions-table write is best-effort
  # and never raises past this method.
  def self.derive(session, intent_id:, intent_dir:, store:, name:, now: Time.now)
    intent_dir_abs = File.expand_path(intent_dir)
    stage = derive_stage(intent_dir_abs)
    has = has_files(intent_dir_abs)
    missing = missing_for_stage(stage, intent_dir_abs) - has

    data = {
      "session" => session,
      "intent" => {
        "id" => intent_id,
        "dir" => File.basename(intent_dir_abs),
        "store" => store,
        "name" => name
      },
      "build" => {
        "stage" => stage,
        "has" => has,
        "missing" => missing,
        "gate_failures" => 0,
        "auto" => false,
        "last_activity" => now.utc.iso8601
      },
      "observe" => {
        "last_transition" => nil,
        "insights_count" => 0,
        "chain_spawned" => []
      },
      "tokens" => {
        "context_pct" => 0,
        "warning_at" => 80,
        "critical_at" => 90
      },
      # Worktree isolation block (intent 73c). Born unprovisioned; arm_auto calls
      # Worktree.provision to fill it. code/store are abs paths or null.
      "worktree" => {
        "code" => nil,
        "code_branch" => nil,
        "store" => nil,
        "store_branch" => nil,
        "provisioned" => false
      },
      # Delivery-lock CACHE block (intent 108, D2). The durable truth is the
      # delivery.lock file in the intent dir; arm fills this cache from it.
      "lock" => {
        "owner_session" => nil,
        "acquired_at" => nil,
        "host" => nil,
        "type" => nil,
        "delegates" => []
      }
    }

    register_session(store: store, session: session, intent_id: intent_id,
                      cwd: intent_dir_abs, auto: false, now: now)
    data
  end

  # Best-effort sessions-table write shared by derive/arm/repair_lock (fail
  # open: a DB error here must never break the caller's in-memory bridge_data).
  def self.register_session(store:, session:, intent_id:, cwd:, auto:, now: Time.now)
    Plastic::DB.session_register(
      File.dirname(store), session_id: session_key(session, intent_id),
      host: Socket.gethostname, pid: Process.pid, cwd: cwd,
      active_intent_id: intent_id, auto: auto, now: now
    )
  rescue StandardError => e
    $stderr.puts "plastic: session register failed, continuing in-memory only: #{e.message}"
    nil
  end

  def self.update_session(store:, session:, intent_id:, now: Time.now, **fields)
    Plastic::DB.session_update(File.dirname(store), session_id: session_key(session, intent_id),
                               now: now, **fields)
  rescue StandardError => e
    $stderr.puts "plastic: session update failed: #{e.message}"
    nil
  end

  def self.end_session(store:, session:, intent_id:)
    Plastic::DB.session_end(File.dirname(store), session_id: session_key(session, intent_id))
  rescue StandardError => e
    $stderr.puts "plastic: session end failed: #{e.message}"
    nil
  end

  # Gate check: returns nil if allowed, or an error message string if blocked
  def self.check_gate(intent_dir, file_being_written)
    basename = File.basename(file_being_written)

    case basename
    when "spec.md"
      ifile = intent_file(intent_dir)
      unless File.exist?(ifile) && File.read(ifile).include?("## Intent")
        return "Cannot start Why — What is incomplete (#{File.basename(ifile)} missing or no ## Intent)"
      end
    when "plan.md"
      unless stage_file_present?("#{intent_dir}/spec.md")
        return "Cannot start How — Why is incomplete (spec.md missing)"
      end
    when "checklist.md"
      unless stage_file_present?("#{intent_dir}/plan.md") && File.directory?("#{intent_dir}/actions")
        return "Cannot complete How — plan.md or actions/ missing"
      end
    when "outcome.md"
      checklist = "#{intent_dir}/checklist.md"
      if stage_file_present?(checklist)
        content = File.read(checklist)
        unchecked = content.scan(/^- \[ \]/).length
        if unchecked > 0
          return "Cannot complete Exec — #{unchecked} unchecked items in checklist.md"
        end
      end
    end

    nil # no gate violation
  end

  PROJECT_CONFIG_DEFAULTS = {
    "governing_docs" => ["AGENTS.md"],
    "release" => {
      "on_complete" => "commit",
    },
  }.freeze

  def self.read_project_config(slug)
    path = File.join(Dir.home, ".plastic", "projects", slug, "project.yml")
    config = if File.exist?(path)
               YAML.safe_load(File.read(path)) || {}
             else
               {}
             end

    deep_merge(PROJECT_CONFIG_DEFAULTS, config)
  rescue => e
    $stderr.puts "Warning: failed to read project config for #{slug}: #{e.message}"
    PROJECT_CONFIG_DEFAULTS.dup
  end

  # --- Auto mode (intent 27) ---

  # Shared arming spine (intent 96): resolve the session key, derive intent state,
  # set the caller-controlled auto flag, acquire the delivery lock, provision the
  # per-intent worktrees, persist, and purge terminal bridges. arm_auto (auto: true)
  # and arm_guided (auto: false) are thin delegators so the lock-stamp + provision
  # behaviour stays identical across both modes. Works even when no bridge exists
  # yet (mid-session intent creation).
  def self.arm(session, intent_id:, intent_dir:, store:, name:, auto:)
    key = resolve_session(session, intent_id: intent_id, store: store)
    if blank?(session) && blank?(ENV["CLAUDE_CODE_SESSION_ID"])
      $stderr.puts "plastic: no session id available; arming with derived bridge key #{key}"
    end
    data = derive(key, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name)
    data["build"]["auto"] = auto

    # Acquire the delivery lease (D1/D2, cutover intent 41 ACTION_10):
    # session-keyed, atomic (BEGIN IMMEDIATE check-then-insert), in
    # `lock_leases`. The bridge lock block is a cache of the row. No
    # delivery.lock file is written anywhere (AC7): the lease is the ONLY
    # delivery-lock state. DB-unavailable fails OPEN (arm proceeds without
    # lock enforcement, advisory only) rather than blocking arming outright.
    intent_dir_abs = File.expand_path(intent_dir)
    store_home = File.dirname(store)
    status, lease_row = Plastic::DB.lease_acquire(store_home, intent_id, session: key, host: Socket.gethostname)
    case status
    when :acquired, :owned
      data["lock"] = lock_cache_from_lease(store_home, lease_row)
    when :held
      raise LockHeldError, "delivery lock for intent #{intent_id} is held by " \
        "session #{lease_row && lease_row['owner_session']}; run /plastic-lock status"
    when :stale
      raise LockHeldError, "delivery lock for intent #{intent_id} is stale " \
        "(owner #{lease_row && lease_row['owner_session']}); run /plastic-lock " \
        "reclaim to take it over with an audit"
    when :fail_open
      $stderr.puts "plastic: lease DB unavailable for intent #{intent_id}; " \
        "arming without lock enforcement (advisory)"
    end

    # Provision the per-intent worktrees (mandatory code worktree for project
    # intents; fail-open for non-git / global-only). Never let a provision error
    # break arming: the lock and auto flag still matter.
    begin
      Worktree.provision(data)
    rescue => e
      $stderr.puts "plastic: worktree provision raised, continuing unprovisioned: #{e.message}"
    end

    update_session(store: store, session: key, intent_id: intent_id, auto: auto,
                   cwd: data.dig("worktree", "code") || intent_dir_abs)
    purge_done_bridges(session: key, store: store)
    data
  end
  private_class_method :arm

  # Arm auto mode for a session+intent. Works even when no bridge exists yet
  # (mid-session intent creation). Re-derives intent state, then sets build.auto.
  def self.arm_auto(session, intent_id:, intent_dir:, store:, name:)
    arm(session, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name, auto: true)
  end

  # Acquire the delivery lock WITHOUT auto mode (intent 96 / Start guided branch).
  # Mirrors arm_auto's lock-stamp + worktree provision but leaves build.auto = false.
  # Same signature as arm_auto; disarm_auto (mode-agnostic) releases a guided lock.
  def self.arm_guided(session, intent_id:, intent_dir:, store:, name:)
    arm(session, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name, auto: false)
  end

  # Degrade path for disarm_auto when no intent_id is given (intent 131): the
  # session's sole per-intent row when there is exactly one, else nil (no
  # legacy bare-key fallback in the DB world: every register call always
  # carries an intent_id, so a bare row never exists post-cutover). Keeps the
  # common single-intent auto path working without every caller having to name
  # the intent id explicitly.
  def self.sole_session_row(session, store_home:)
    conn = Plastic::DB.connect(store_home)
    return nil if conn.nil?
    rows = Plastic::DB::Sessions.all(conn).select { |r| r["session_id"].to_s.start_with?("#{session}--") }
    rows.length == 1 ? rows.first : nil
  rescue StandardError
    nil
  end

  # Disarm. No-op if no session row exists. End-tail order (D6): worktrees are
  # merged/removed FIRST (the verify step is the caller's, before disarm),
  # then the delivery lock is cleared, and only then does the session become
  # GC-eligible. purge_done_bridges enforces the same order defensively by
  # skipping any row whose intent still holds a lock.
  #
  # Takes intent_id (intent 131): a session can own SEVERAL live rows (one per
  # concurrent intent), so disarm must target ONE of them. When intent_id is
  # nil, degrades to the session's sole row (see sole_session_row). `store:` is
  # optional (new kwarg, mirrors arm/derive): pass the intent's store dir when
  # known (hermetic tests, or a caller that already knows it); otherwise it is
  # resolved from cwd exactly like discover_bridge does.
  def self.disarm_auto(session, intent_id: nil, store: nil)
    store_home = store ? File.dirname(store) : resolve_store_home
    conn = Plastic::DB.connect(store_home)
    return nil if conn.nil?

    row = if blank?(intent_id)
            sole_session_row(session, store_home: store_home)
          else
            Plastic::DB::Sessions.active_for(conn, session: session_key(session, intent_id), cwd: nil)
          end
    return nil if row.nil?
    intent_id ||= row["active_intent_id"]
    return nil if blank?(intent_id)

    intent_dir = Dir.glob(File.join(store_home, "store", "#{intent_id}--*")).first
    return nil if intent_dir.nil?

    lock_row = Plastic::DB::Sessions.current_lock_row(conn, intent_id)
    data = Plastic::DB::Sessions.to_bridge_data(row, intent_dir: intent_dir, lock_row: lock_row)
    data["build"]["auto"] = false

    # Rebuild the full worktree block (code/code_branch/store/store_branch) so
    # Worktree.release can find both worktrees: the sessions row only carries
    # `cwd` (-> worktree.code), never the store-worktree path, so this recomputes
    # it the same PURE, deterministic way Worktree.provision derived it
    # originally (no git calls; repo_for is a plain projects.yml read).
    intent_slug = Worktree.slug_from_dir(intent_dir)
    slug = Worktree.slug_for_store(File.join(store_home, "store"), home: Dir.home)
    data["worktree"] = Worktree.paths(slug: slug, intent_id: intent_id, intent_slug: intent_slug, home: Dir.home)
                               .merge("provisioned" => !blank?(row["cwd"]))

    # Release the worktrees the matching arm provisioned (intent 73c). Non-fatal:
    # a release error must not block disarming. CLEANUP (73c3) refines the
    # merge-vs-remove policy on the completion/release path.
    begin
      Worktree.release(data)
    rescue => e
      $stderr.puts "plastic: worktree release raised, continuing: #{e.message}"
    end

    owner = data.dig("lock", "owner_session")
    owner = session if blank?(owner)
    begin
      Plastic::DB.lease_release(store_home, intent_id, session: owner)
    rescue StandardError => e
      $stderr.puts "plastic: lease release failed: #{e.message}"
    end
    data["lock"] = { "owner_session" => nil, "acquired_at" => nil,
                     "host" => nil, "type" => nil, "delegates" => [] }

    end_session(store: File.join(store_home, "store"), session: session, intent_id: intent_id)
    purge_done_bridges(session: session, store: File.join(store_home, "store"))
    data
  end

  # One deterministic, idempotent repair (intent 108, D5; cutover intent 41
  # ACTION_10): diagnose, rebuild the delivery lease AND the session row from
  # disk truth for the current session. NEVER touches a fresh foreign lease
  # (reports "held"). There is no more "corrupt" state to repair (a DB row
  # cannot be unparseable JSON), and an expired foreign lease is no longer a
  # "stale, explicit reclaim only" condition to report here either: leases
  # fail open on expiry by construction, so repair may simply take it over.
  # Two entry points call this: the plastic-lock CLI and
  # /plastic-intent-starting (self-healing boarding).
  def self.repair_lock(session, intent_id:, intent_dir:, store:, name:, now: Time.now)
    key = resolve_session(session, intent_id: intent_id, store: store)
    dir = File.expand_path(intent_dir)
    store_home = File.dirname(store)
    actions = []

    conn = Plastic::DB.connect(store_home)
    if conn.nil?
      actions << "DB unavailable; nothing to repair (fail open)"
      return { "status" => "repaired", "actions" => actions, "lock" => nil, "session" => key }
    end

    row = Plastic::DB::Leases.current(conn, intent_id)
    if row && !Plastic::DB::Leases.authorized?(conn, intent_id, session: key) &&
       Plastic::DB::Leases.fresh?(conn, intent_id, now: now)
      return { "status" => "held", "owner" => row["owner_session"],
               "actions" => actions, "session" => key }
    end

    if row && Plastic::DB::Leases.authorized?(conn, intent_id, session: key)
      Plastic::DB.lease_renew(store_home, intent_id, session: key, now: now)
      lease_row = Plastic::DB::Leases.current(conn, intent_id)
      role = lease_row["owner_session"].to_s == key ? "owner" : "delegate"
      actions << "lease kept (#{role})"
    elsif row
      # Foreign AND expired (the only way past the "held" return above):
      # leases fail open on expiry, so repair may safely take over rather
      # than report a stale/explicit-reclaim-only condition (mirrors the old
      # repair_lock's "migrate legacy state" self-healing intent). A plain
      # lease_acquire would only report :stale here without acquiring, which
      # would misattribute the foreign row's data as this session's own.
      status, lease_row = Plastic::DB.lease_takeover(store_home, intent_id, session: key, now: now)
      actions << "lease #{status} (expired foreign lease reclaimed)"
    else
      status, lease_row = Plastic::DB.lease_acquire(store_home, intent_id, session: key, now: now)
      actions << "lease #{status}"
    end

    previous = Plastic::DB::Sessions.active_for(conn, session: session_key(key, intent_id), cwd: nil)
    auto = !!(previous && previous["auto"].to_i == 1)

    data = derive(key, intent_id: intent_id, intent_dir: dir, store: store, name: name, now: now)
    data["build"]["auto"] = auto
    data["lock"] = lock_cache_from_lease(store_home, lease_row)
    update_session(store: store, session: key, intent_id: intent_id, auto: auto, now: now)
    actions << "bridge rebuilt from disk (stage #{data['build']['stage']})"

    { "status" => "repaired", "actions" => actions,
      "lock" => lease_row, "session" => key }
  end

  # Decide whether a code edit should be blocked while auto mode is armed.
  # Returns a reason string to BLOCK, or nil to ALLOW.
  #
  # Blocks iff: auto armed AND intent hasn't reached How (stage what/why) AND the
  # target is project code — i.e. NOT under ~/.plastic and NOT inside the intent dir.
  def self.code_gate_decision(bridge_data, file_path, home: Dir.home)
    return nil unless bridge_data.is_a?(Hash)
    build = bridge_data["build"] || {}
    return nil unless build["auto"] == true

    intent_info = bridge_data["intent"] || {}
    store = intent_info["store"]
    dir = intent_info["dir"]
    return nil unless store && dir
    intent_dir_abs = File.expand_path("#{store}/#{dir}")

    # "How reached" = the plan triplet exists. Gate by artifact presence, not the
    # stage label (derive_stage returns "how" as soon as spec.md exists, before any
    # plan). Code edits stay blocked until plan.md + checklist.md are both present.
    reached_how = stage_file_present?("#{intent_dir_abs}/plan.md") &&
                  stage_file_present?("#{intent_dir_abs}/checklist.md")
    return nil if reached_how

    file_abs = File.expand_path(file_path.to_s)
    plastic_home = File.expand_path(File.join(home, ".plastic"))
    return nil if file_abs == plastic_home || file_abs.start_with?("#{plastic_home}/")
    return nil if file_abs == intent_dir_abs || file_abs.start_with?("#{intent_dir_abs}/")

    id = intent_info["id"]
    "intent #{id} has not reached How — write plan.md + checklist.md before " \
      "editing project code. Run plastic-auto or plastic-writing-plans first. " \
      "(blocked edit: #{file_abs})"
  end

  # --- Solo-mode detection (intent 128, cutover intent 41 ACTION_10) ----------
  #
  # Positive-only confirmation that exactly one session is delivering, read
  # from `lock_leases` rows (never the /tmp bridge cache, D2). Used to relax
  # the two ARBITRATION gates (lock_gate_decision, worktree_gate_decision) from
  # a hard deny to an advisory allow when there is nothing to arbitrate.
  #
  # SOLO iff exactly ONE fresh delivery-grain lease exists across scan_roots
  # (each a STORE dir; one plastic.db per store, so each is its own
  # connection), that lease's owner_session equals the resolved session, and
  # it has no registered delegates. Any ambiguity (more than one fresh lease,
  # including several under the SAME owner_session, which reads as
  # parallel-in-play), a foreign owner, a registered delegate, a
  # blank/unresolvable session, or any error during the scan all return false
  # (fail-closed direction preserved). A lease row can never be "unreadable"
  # the way a hand-parsed JSON file could, so the old corrupt-lock ambiguity
  # case is structurally impossible now.
  def self.solo_delivery?(scan_roots:, session:, ttl: Plastic::DB::Leases::TTL_SECONDS, now: Time.now)
    return false if blank?(session)

    store_homes = Array(scan_roots).compact.map { |root| File.dirname(File.expand_path(root.to_s)) }.uniq
    fresh = store_homes.flat_map do |store_home|
      conn = Plastic::DB.connect(store_home)
      next [] if conn.nil?
      Plastic::DB::Leases.fresh_delivery_rows(conn, now: now).map { |row| [store_home, row] }
    end

    return false unless fresh.length == 1

    store_home, row = fresh.first
    return false unless row["owner_session"].to_s == session.to_s

    conn = Plastic::DB.connect(store_home)
    Plastic::DB::Leases.delegates_for(conn, row["id"]).empty?
  rescue StandardError
    false
  end

  # One terse advisory line (no em-dashes), then ALLOW (nil). Shared by both
  # arbitration gates so a relaxed deny always logs the same shape.
  def self.solo_allow(id, reason)
    $stderr.puts "plastic: solo delivery confirmed for intent #{id} (#{reason}); allowing"
    nil
  end

  # --- Fail-closed lock gate (intent 96, cutover intent 41 ACTION_10) --------

  # Returns a reason String to BLOCK, or nil to ALLOW. Decides from the
  # `lock_leases` delivery-grain row for the TARGET intent (D2): the bridge
  # argument only supplies a fallback session id, so a missing or disagreeing
  # bridge never changes the verdict. Every deny names the exact resolving
  # command (D5). ALLOW: non-intent paths, not-yet-active intents, any session
  # the lease names as owner or delegate, and (new in this cutover) an EXPIRED
  # lease -- leases fail open on expiry by construction (Plastic::DB::Leases,
  # D-notes "fail open, always"): no explicit reclaim is required, unlike the
  # retired file lock. DB-unavailable is its own fail-open path, distinct from
  # "no lease at all" (which still denies: dormancy is not the same as never
  # having armed).
  def self.lock_gate_decision(bridge_data, file_path, session: nil,
                              ttl: Plastic::DB::Leases::TTL_SECONDS, now: Time.now, home: Dir.home)
    return nil if blank?(file_path)

    target_dir = intent_dir_for(file_path)
    return nil unless target_dir
    id = intent_id_from_dir(target_dir)
    store = File.dirname(target_dir)
    return nil unless id && intent_active?(id, store: store)

    sess = session
    sess = bridge_data["session"] if blank?(sess) && bridge_data.is_a?(Hash)

    # Solo-mode detection (intent 128): scan this intent's store plus the
    # global store under `home` for fresh delivery leases. Computed once; used
    # at the arbitration deny below to relax a hard deny to an advisory allow
    # when solo delivery is positively confirmed.
    scan_roots = [store, File.join(File.expand_path(home), ".plastic", "store")]
    solo = solo_delivery?(scan_roots: scan_roots, session: sess, ttl: ttl, now: now)

    store_home = File.dirname(store)
    conn = Plastic::DB.connect(store_home)
    if conn.nil?
      $stderr.puts "plastic: lock gate DB unavailable for intent #{id}; allowing (advisory)"
      return nil
    end

    row = Plastic::DB::Leases.current(conn, id)
    if row.nil?
      return solo_allow(id, "no delivery lock") if solo
      return "no delivery lock held for intent #{id}; run /plastic-intent-starting " \
        "to lock and begin"
    end

    return nil if Plastic::DB::Leases.authorized?(conn, id, session: sess)

    unless Plastic::DB::Leases.fresh?(conn, id, now: now)
      $stderr.puts "plastic: lock gate advisory - intent #{id}'s delivery lease is " \
        "expired (owner #{row['owner_session']}); allowing (leases fail open on expiry)"
      return nil
    end

    return solo_allow(id, "fresh delivery lock") if solo
    "intent #{id} delivery lock is held by session " \
      "#{row['owner_session']}. Back off; if you are the owner's " \
      "subagent, the owner must run: plastic-lock delegate " \
      "--intent-dir #{target_dir} --session <your-session-id>. " \
      "Inspect with /plastic-lock status"
  end

  # A session holds an intent's lock iff the `lock_leases` delivery-grain row
  # names it as owner or delegate (D1/D4). The bridge is only a cache: the
  # lease decides, so a wiped /tmp or a clobbered bridge never strands the
  # owner. No pid is consulted anywhere.
  def self.holds_live_lock?(bridge_data, session: nil)
    sess = session
    sess = bridge_data["session"] if blank?(sess) && bridge_data.is_a?(Hash)
    return false if blank?(sess)
    dir = bridge_intent_dir(bridge_data)
    return false unless dir
    id = intent_id_from_dir(dir)
    return false unless id
    store = bridge_data.is_a?(Hash) ? bridge_data.dig("intent", "store") : nil
    return false if blank?(store)
    conn = Plastic::DB.connect(File.dirname(store))
    return false if conn.nil?
    Plastic::DB::Leases.authorized?(conn, id, session: sess)
  rescue StandardError
    false
  end

  # "<id>" from a ".../store/<id>--<slug>" dir, else nil.
  def self.intent_id_from_dir(dir)
    base = File.basename(dir.to_s)
    base.include?("--") ? base.split("--", 2).first : nil
  end

  # --- Worktree isolation gate (intent 73c2) ---

  # Returns a reason String to BLOCK, or nil to ALLOW. Two independent rules,
  # both fail-open by construction:
  #
  #   1. When the bridge has a provisioned code worktree, a code edit (a target
  #      outside ~/.plastic and outside this intent's store dir) MUST land inside
  #      worktree["code"]; otherwise BLOCK and name the expected worktree path.
  #   2. When the target lives inside ANOTHER intent's store dir whose bridge lock
  #      is held by a LIVE non-owner session, BLOCK (non-owner edit to an active
  #      intent).
  #
  # Fails open (returns nil) when provisioned is false (non-git / global-only) or
  # the bridge carries no worktree/lock blocks. Logs nothing on the allow path.
  def self.worktree_gate_decision(bridge_data, file_path, home: Dir.home, current_session: nil)
    return nil unless bridge_data.is_a?(Hash)
    return nil if blank?(file_path)

    file_abs = File.expand_path(file_path.to_s)
    plastic_home = File.expand_path(File.join(home, ".plastic"))
    under_plastic = file_abs == plastic_home || file_abs.start_with?("#{plastic_home}/")

    intent_info = bridge_data["intent"] || {}
    store = intent_info["store"]
    dir = intent_info["dir"]
    intent_dir_abs = (store && dir) ? File.expand_path("#{store}/#{dir}") : nil
    under_own_intent = intent_dir_abs &&
                       (file_abs == intent_dir_abs || file_abs.start_with?("#{intent_dir_abs}/"))

    # Solo-mode detection (intent 128): current session first, else the
    # bridge's own session; scan roots are this intent's store, the global
    # store under `home`, AND the EDIT TARGET's own store (when the target
    # lives inside a store dir), so a live foreign lock on the intent being
    # edited is never invisible to the scan just because it belongs to a
    # different project than the acting bridge's own store (review finding 1;
    # duplicate roots are harmless, solo_delivery? dedupes). Computed once;
    # used by both rules below.
    sess = blank?(current_session) ? bridge_data["session"] : current_session
    target_store = parse_store_target(file_abs, plastic_home)&.fetch(:store, nil)
    scan_roots = [store, File.join(plastic_home, "store"), target_store]
    solo = solo_delivery?(scan_roots: scan_roots, session: sess)

    # Rule 1 (fixed in intent 108, D7): confinement applies ONLY to paths
    # inside the project repo. The repo root is derived from the provisioned
    # code worktree path, which is <repo>/.claude/worktrees/{id}--{slug} by
    # construction, so no git call is needed. Paths outside the repo (agent
    # memory dirs, scratch files, unrelated checkouts) are not this gate's
    # business; the 2026-07-02 memory-dir denial came from treating everything
    # outside the worktree as the shared checkout.
    worktree = bridge_data["worktree"] || {}
    if worktree["provisioned"] == true
      code = worktree["code"].to_s
      if !blank?(code) && !under_plastic && !under_own_intent
        code_abs = File.expand_path(code)
        repo_abs = File.expand_path(File.join(code_abs, "..", "..", ".."))
        inside_repo = file_abs == repo_abs || file_abs.start_with?("#{repo_abs}/")
        inside_code = file_abs == code_abs || file_abs.start_with?("#{code_abs}/")
        if inside_repo && !inside_code
          id = intent_info["id"]
          return solo_allow(id, "worktree confinement") if solo
          return "intent #{id} is isolated to its worktree - edit project code " \
                 "inside #{code_abs}, not the shared checkout. (blocked edit: #{file_abs})"
        end
      end
    end

    # Rule 2: do not edit another intent's locked, live store dir.
    if under_plastic
      reason = non_owner_store_edit_reason(file_abs, plastic_home, intent_dir_abs,
                                           home: home, current_session: current_session,
                                           own_session: bridge_data["session"])
      if reason
        return solo_allow(intent_info["id"], "non-owner store edit") if solo
        return reason
      end
    end

    nil
  end

  # Helper for rule 2. A store dir is `<plastic_home>/store/{id}--{slug}` (global)
  # or `<plastic_home>/projects/{slug}/store/{id}--{slug}` (project). When the
  # edit target sits inside such a dir that is NOT this intent's own dir, and a
  # live non-owner session holds that intent's bridge lock, BLOCK.
  def self.non_owner_store_edit_reason(file_abs, plastic_home, own_intent_dir_abs,
                                       home:, current_session:, own_session:)
    return nil if own_intent_dir_abs &&
                  (file_abs == own_intent_dir_abs || file_abs.start_with?("#{own_intent_dir_abs}/"))

    parsed = parse_store_target(file_abs, plastic_home)
    return nil unless parsed

    session = blank?(current_session) ? own_session : current_session
    held = Worktree.lock_held_by_other?(
      intent_id: parsed[:id], store: parsed[:store],
      current_session: session, home: home,
    )
    return nil unless held

    "intent #{parsed[:id]} is owned by another live session — its delivery lock " \
      "is held elsewhere. Back off; do not edit #{file_abs}."
  end

  # Resolve an edit target inside a store to {id:, store:} for the intent dir it
  # belongs to, or nil if the path is not inside an `{id}--{slug}` intent dir.
  def self.parse_store_target(file_abs, plastic_home)
    rels = []
    global_store = File.join(plastic_home, "store")
    if file_abs.start_with?("#{global_store}/")
      rels << [file_abs[(global_store.length + 1)..], global_store]
    end
    projects = File.join(plastic_home, "projects")
    if file_abs.start_with?("#{projects}/")
      tail = file_abs[(projects.length + 1)..].to_s
      parts = tail.split(File::SEPARATOR)
      if parts.length >= 2 && parts[1] == "store"
        pstore = File.join(projects, parts[0], "store")
        rels << [file_abs[(pstore.length + 1)..], pstore]
      end
    end

    rels.each do |rel, store_dir|
      next if blank?(rel)
      first = rel.split(File::SEPARATOR).first.to_s
      idx = first.index("--")
      next unless idx && idx > 0
      return { id: first[0...idx], store: store_dir }
    end
    nil
  end

  # --- Bash-edit gate (intent 27a) ---

  # Extract the set of file paths a Bash command writes to. Conservative by
  # design: it is acceptable to miss exotic forms, but it must NOT flag reads
  # or /dev/null. Returns an Array of path strings (possibly relative).
  #
  # Covered write vectors: redirection (>, >>, including heredoc `cat > f <<EOF`),
  # tee / tee -a, sed -i / sed -i.bak, cp/mv (last non-flag arg), dd of=.
  def self.bash_write_targets(command)
    return [] unless command.is_a?(String)

    targets = []
    targets.concat(bash_redirect_targets(command))
    # Split on command separators for per-segment utility parsing.
    command.split(/[;\n]|&&|\|\||\|/).each do |segment|
      targets.concat(bash_utility_targets(segment))
      targets.concat(interpreter_write_targets(segment))
    end
    targets.uniq
  end

  # Redirections: `> path` / `>> path`, but not fd dups (`2>&1`) or /dev/null.
  # A leading digit (fd number) before > is fine; `>&` is a dup and excluded.
  # Quote- and heredoc-aware: a `>` inside a single/double-quoted span or inside a
  # heredoc body is NOT a redirect. Fails OPEN (returns []) on an ambiguous parse
  # (unbalanced quote or unterminated heredoc) rather than guessing a target.
  def self.bash_redirect_targets(command)
    return [] unless command.is_a?(String)
    scannable = scannable_redirect_text(command)
    return [] if scannable.nil? # ambiguous parse -> fail open
    targets = []
    scannable.scan(/\d*>>?(?!&)\s*([^\s;|&<>]+)/) do |m|
      path = m[0]
      next if path.nil? || path.empty?
      next if dev_null?(path)
      targets << path
    end
    targets
  end

  # Return a copy of `command` in which single-quoted spans, double-quoted spans,
  # and heredoc bodies are blanked to spaces, so the redirect regex only ever sees
  # operators that are genuinely outside quotes and heredoc bodies. Returns nil on
  # an ambiguous parse (a line ends inside a quote, or a heredoc is never closed).
  def self.scannable_redirect_text(command)
    out = +""
    pending = [] # queue of {word:, dash:} heredoc terminators awaiting bodies
    command.split("\n", -1).each do |line|
      if pending.any?
        term = pending.first
        probe = term[:dash] ? line.sub(/\A\t+/, "") : line
        pending.shift if probe == term[:word]
        out << "\n" # heredoc body/terminator line contributes nothing scannable
        next
      end
      masked, openers, balanced = mask_redirect_line(line)
      return nil unless balanced # unbalanced quote on this line -> ambiguous
      out << masked << "\n"
      pending.concat(openers)
    end
    return nil if pending.any? # unterminated heredoc -> ambiguous
    out
  end

  # Walk one normal (non-heredoc-body) line, masking quoted spans to spaces and
  # recognizing heredoc openers. Returns [masked_line, [heredoc_openers], balanced?].
  def self.mask_redirect_line(line)
    out = +""
    openers = []
    state = :normal
    i = 0
    n = line.length
    while i < n
      c = line[i]
      case state
      when :single
        if c == "'" || c == "<" || c == ">"
          out << " "
        else
          out << c
        end
        state = :normal if c == "'"
        i += 1
      when :double
        if c == "\\" && i + 1 < n
          out << "  "
          i += 2
        else
          if c == '"' || c == "<" || c == ">"
            out << " "
          else
            out << c
          end
          state = :normal if c == '"'
          i += 1
        end
      else # :normal
        if c == "'"
          out << " "; state = :single; i += 1
        elsif c == '"'
          out << " "; state = :double; i += 1
        elsif c == "<" && line[i + 1] == "<"
          m = line[i..].match(/\A<<(-?)\s*("|')?([A-Za-z0-9_][A-Za-z0-9_]*)\2?/)
          if m
            openers << { word: m[3], dash: m[1] == "-" }
            out << (" " * m[0].length)
            i += m[0].length
          else
            out << "<<"; i += 2 # here-string / no valid word: leave as-is
          end
        else
          out << c; i += 1
        end
      end
    end
    [out, openers, state == :normal]
  end

  def self.bash_utility_targets(segment)
    tokens = segment.strip.split(/\s+/)
    return [] if tokens.empty?

    # Find the utility name, skipping env-style assignments.
    idx = 0
    idx += 1 while tokens[idx] && tokens[idx].include?("=") && tokens[idx] !~ /^-/ && !tokens[idx].start_with?("of=")
    util = File.basename(tokens[idx].to_s)
    args = tokens[(idx + 1)..] || []

    case util
    when "tee"
      tee_targets(args)
    when "sed"
      sed_targets(args)
    when "cp", "mv"
      copy_move_targets(args)
    when "dd"
      dd_targets(tokens)
    else
      []
    end
  end

  def self.tee_targets(args)
    args.reject { |a| a.start_with?("-") || dev_null?(a) }
  end

  def self.sed_targets(args)
    # In-place only: -i or -i.bak (suffix attached). Otherwise sed reads.
    inplace = args.any? { |a| a == "-i" || a.start_with?("-i") }
    return [] unless inplace
    files = args.reject { |a| a.start_with?("-") }
    # sed args: script then file(s). First non-flag is the script expression
    # unless an -e/-f was used; conservatively treat the LAST non-flag as file.
    files.empty? ? [] : [files.last].reject { |f| dev_null?(f) }
  end

  def self.copy_move_targets(args)
    files = args.reject { |a| a.start_with?("-") }
    return [] if files.length < 2
    dest = files.last
    dev_null?(dest) ? [] : [dest]
  end

  def self.dd_targets(tokens)
    tokens.each_with_object([]) do |t, acc|
      next unless t.start_with?("of=")
      path = t.sub("of=", "")
      acc << path unless path.empty? || dev_null?(path)
    end
  end

  def self.dev_null?(path)
    path == "/dev/null" || path.start_with?("/dev/")
  end

  # --- Interpreter inline-code writes (intent 108, D7) ---

  INTERPRETER_RE = /\b(ruby|python3?|perl|node)\b(?:\s+\S+)*?\s+(-e|-c)\s+(.+)\z/m.freeze

  # Write verbs that mark inline code as file-mutating. Conservative: reads
  # (File.read, puts) never match.
  WRITE_VERB_RE = /File\.(?:write|binwrite|open)|IO\.write|FileUtils\.|
                   open\s*\([^)]*["'][wa]|writeFileSync|fs\.write/x.freeze

  # Quoted absolute or ~/ paths inside the inline code.
  INLINE_PATH_RE = %r{["']((?:/|~/)[^"']+)["']}.freeze

  # Paths an interpreter one-liner writes. Flagged only when the inline code
  # has BOTH a write verb AND a quoted absolute path; everything else (reads,
  # ARGV-driven paths, the sanctioned arm one-liners) yields no targets.
  def self.interpreter_write_targets(segment)
    m = INTERPRETER_RE.match(segment.to_s)
    return [] unless m
    util, flag, code = m[1], m[2], m[3]
    expected = { "ruby" => "-e", "python" => "-c", "python3" => "-c",
                 "perl" => "-e", "node" => "-e" }[util]
    return [] unless flag == expected
    return [] unless WRITE_VERB_RE.match?(code)
    code.scan(INLINE_PATH_RE).flatten.map { |p| File.expand_path(p) }
  end

  # Decide whether a Bash command should be blocked. Every write target runs
  # through the SAME policy stack as a direct tool write: the auto-mode code
  # gate AND the delivery-lock gate (intent 108, D7), so bash and interpreter
  # writes cannot bypass the lock. Returns the first block reason, or nil.
  def self.bash_gate_decision(bridge_data, command, cwd:, home: Dir.home, session: nil)
    bash_write_targets(command).each do |target|
      abs = File.absolute_path?(target) ? target : File.join(cwd, target)
      abs = File.expand_path(abs)
      reason = code_gate_decision(bridge_data, abs, home: home) ||
               lock_gate_decision(bridge_data, abs, session: session)
      return reason if reason
    end
    nil
  end

  # A TRAILING `# plastic-ok` shell comment: the auditable escape for
  # sanctioned bash/interpreter writes (mirrors the retrieval gate's
  # `# qmd-ok`). The hook logs every use to ~/.plastic/.cache/gate-escapes.log.
  PLASTIC_OK_RE = /(?:\A|\s)#\s*plastic-ok\s*\z/.freeze

  def self.bash_escape?(command)
    PLASTIC_OK_RE.match?(command.to_s.chomp)
  end

  def self.deep_merge(base, overlay)
    result = base.dup
    overlay.each do |key, value|
      if value.is_a?(Hash) && result[key].is_a?(Hash)
        result[key] = deep_merge(result[key], value)
      else
        result[key] = value
      end
    end
    result
  end
end
