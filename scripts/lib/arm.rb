# encoding: UTF-8
# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "lock"
require_relative "worktree"
require_relative "session_ledger"
require_relative "savepoint"

# Arm - how an auto team takes an intent and gives it back (intent 307).
#
# Three durable facts make a delivery: the delivery lock in the intent
# directory (who owns it), the code worktree under the project repo (where
# the code lands), and the per-session pointer in the global store's `.tmp/`
# (which intent this session records into; a day id means the day ledger).
# Before 2.0 a fourth thing, a `/tmp` bridge JSON, cached all three plus a
# stage snapshot; ruling 6 of intent 296 retired it, and this module is what
# replaced the bridge's arm, disarm, and repair methods (removed in 2.0, intent 307).
#
# Pure and dependency-injected: every path and clock is an argument, every git
# call goes through an injected runner, and the only environment read is the
# `env:` value the caller passes to `resolve_session`. Nothing here raises for
# a lock outcome; callers get a status and decide.
module Arm
  module_function

  STATUSES = %i[acquired owned held stale excluded corrupt].freeze

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # Deterministic, session-less key derived from the store and the intent id,
  # for headless runs that carry no session id at all (moved from Bridge).
  def derive_key(store, intent_id)
    "auto-" + Digest::SHA256.hexdigest("#{store}/#{intent_id}")[0, 10]
  end

  # The session that keys a lock: the explicit id, else the env id the caller
  # read (CLAUDE_CODE_SESSION_ID), else the derived key. Never nil.
  def resolve_session(explicit, env: nil, store:, intent_id:)
    return explicit.to_s.strip unless blank?(explicit)
    return env.to_s.strip unless blank?(env)
    derive_key(store, intent_id)
  end

  # --- derivations (no I/O beyond Dir.exist?) ---------------------------------

  def intent_id_for(intent_dir)
    File.basename(intent_dir.to_s).split("--", 2).first
  end

  def store_for(intent_dir)
    File.dirname(File.expand_path(intent_dir))
  end

  # The home (parent of `.plastic`) an intent dir belongs to, else the given
  # fallback. A sandboxed store never resolves to the real Dir.home.
  def home_for(intent_dir, home: Dir.home)
    Worktree.home_from_store(store_for(intent_dir)) || home
  end

  def global_store(home)
    File.join(File.expand_path(home), ".plastic", "store")
  end

  # The minimal hash Worktree.provision, release, and finish consume: the
  # intent block plus, when asked, the derived worktree block.
  def bridge_hash(intent_dir:, home: Dir.home, with_worktree: true)
    dir = File.expand_path(intent_dir)
    data = {
      "intent" => { "id" => intent_id_for(dir), "dir" => File.basename(dir), "store" => store_for(dir) },
    }
    data["worktree"] = worktree_block(intent_dir: dir, home: home) if with_worktree
    data
  end

  # `{code, code_branch, provisioned}` derived from projects.yml and the
  # intent id: the same path provision creates, `provisioned` iff it exists.
  def worktree_block(intent_dir:, home: Dir.home)
    dir = File.expand_path(intent_dir)
    store = store_for(dir)
    h = home_for(dir, home: home)
    slug = Worktree.slug_for_store(store, home: h)
    p = Worktree.paths(slug: slug, intent_id: intent_id_for(dir),
                       intent_slug: Worktree.slug_from_dir(dir), home: h)
    code = p["code"]
    provisioned = !blank?(code) && Dir.exist?(code)
    {
      "code" => provisioned ? code : nil,
      "code_branch" => provisioned ? p["code_branch"] : nil,
      "provisioned" => provisioned,
    }
  end

  # Owner rule 2026-08-31: does this session already have a live top-level
  # pointer pointing SOMEWHERE ELSE (the day ledger or another intent)? A
  # pointer already on this intent is the owner re-arming mid-delivery and
  # stays idempotent. True means a
  # conversation session. Reads only; rescues to false (fail open).
  def preexisting_pointer?(session, home:)
    path = pointer_path(session, home: home)
    File.exist?(path) && !File.read(path).to_s.strip.empty?
  rescue StandardError
    false
  end

  # --- the pointer -------------------------------------------------------------


  def pointer_path(session, home:)
    store = global_store(home)
    SessionLedger.pointer_path(store, SessionLedger.short_session_id(nil, session))
  end

  def read_pointer(session, home:)
    path = pointer_path(session, home: home)
    File.exist?(path) ? File.read(path).strip : nil
  end

  def write_pointer(session, value, home:)
    store = global_store(home)
    SessionLedger.ensure_tmp_root(store)
    path = pointer_path(session, home: home)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{value}\n")
    path
  end

  # --- arm ---------------------------------------------------------------------

  # Take an intent for `session`: acquire delivery.lock (stamped with the run
  # mode and the provenance the caller knows), provision the code worktree
  # (fail-open for a global-only or non-git intent), and point the session at
  # the intent. Returns `{status:, lock:, worktree:, session:, pointer:}`.
  # A held, stale, excluded, or corrupt lock returns that status with the
  # lock data read and touches nothing.
  def arm(intent_dir:, session:, mode: "auto", home: Dir.home, harness: nil,
          agent: nil, model: nil, thread: nil, now: Time.now, runner: Worktree::ShellRunner.new,
          host: Socket.gethostname, allow_inline: false)
    raise ArgumentError, "mode must be auto or guided" unless %w[auto guided].include?(mode.to_s)
    dir = File.expand_path(intent_dir)
    key = resolve_session(session, store: store_for(dir), intent_id: intent_id_for(dir))
    h = home_for(dir, home: home)

    # Owner rule 2026-08-31: the main session never delivers an intent inline.
    # A session that already carries a top-level session pointer is a
    # conversation session (SessionStart wrote it at boot); arming there is
    # inline delivery and is refused BEFORE any lock is taken. A dispatched or
    # headless session has no pre-existing pointer and arms freely.
    # --allow-inline is the explicit owner override. Fail open on read errors:
    # a broken pointer file must never block a legitimate delivery.
    if !allow_inline && preexisting_pointer?(key, home: h) &&
       read_pointer(key, home: h).to_s.strip != intent_id_for(dir)
      return { status: :inline_refused, lock: nil, worktree: nil, session: key, pointer: nil }
    end

    status, lock = Lock.acquire(dir, session: key, host: host, now: now,
                                harness: harness, agent: agent, model: model,
                                thread: thread, run_mode: mode.to_s)
    unless %i[acquired owned].include?(status)
      return { status: status, lock: lock, worktree: nil, session: key, pointer: nil }
    end

    data = bridge_hash(intent_dir: dir, home: h, with_worktree: false)
    begin
      Worktree.provision(data, home: h, runner: runner)
    rescue StandardError => e
      warn "plastic: worktree provision raised, continuing unprovisioned: #{e.message}"
    end

    # The pointer is what the capture and record hooks read; they key on the
    # harness's real session id, so a derived key gets no pointer (nothing would
    # ever read it). A pointer failure warns and never undoes an acquired lock.
    pointer = nil
    unless key == derive_key(store_for(dir), intent_id_for(dir))
      begin
        pointer = write_pointer(key, intent_id_for(dir), home: h)
      rescue StandardError => e
        warn "plastic: session pointer not written (#{e.message}); the lock is held regardless"
      end
    end
    { status: status, lock: lock, worktree: worktree_block(intent_dir: dir, home: h),
      session: key, pointer: pointer }
  end

  # --- disarm ------------------------------------------------------------------

  # Give the intent back: remove the worktree (when `remove`), release the
  # lock as its recorded owner (falling back to `session`), and reset the
  # session pointer to today's day id when it named this intent. Returns
  # the lock release status (:released, :none, :not_owner, or :raised).
  def disarm(intent_dir:, session:, home: Dir.home, runner: Worktree::ShellRunner.new,
             remove: true, now: Time.now)
    dir = File.expand_path(intent_dir)
    h = home_for(dir, home: home)
    key = resolve_session(session, store: store_for(dir), intent_id: intent_id_for(dir))

    begin
      Worktree.release(bridge_hash(intent_dir: dir, home: h), home: h, runner: runner, remove: remove)
    rescue StandardError => e
      warn "plastic: worktree release raised, continuing: #{e.message}"
    end

    lock = Lock.read(dir)
    owner = lock && !blank?(lock["owner_session"]) ? lock["owner_session"] : key
    release_status = begin
      Lock.release(dir, session: owner)
    rescue StandardError => e
      warn "plastic: delivery lock release raised for #{dir}, continuing: #{e.message}"
      :raised
    end

    begin
      reset_pointer(key, intent_id_for(dir), home: h, now: now)
    rescue StandardError => e
      warn "plastic: session pointer not reset (#{e.message})"
    end
    release_status
  end

  # Point the session back at the day ledger, but only when it names `intent_id`.
  def reset_pointer(session, intent_id, home:, now: Time.now)
    current = read_pointer(session, home: home)
    return false unless current == intent_id.to_s
    write_pointer(session, SessionLedger.day_id(now), home: home)
    true
  end

  # --- repair ------------------------------------------------------------------

  # One idempotent repair (the lock half of the bridge's repair, removed in 2.0):
  # remove a corrupt lock, back off from a fresh foreign lock (`held`), report
  # a stale foreign lock (`stale`) for the explicit reclaim verb, keep and
  # enrich an own lock, heartbeat a delegated one, acquire when none, and
  # provision the worktree so the repaired intent has its checkout.
  def repair(intent_dir:, session:, home: Dir.home, now: Time.now, harness: nil,
             agent: nil, model: nil, thread: nil, run_mode: nil, hint_harness: nil,
             runner: Worktree::ShellRunner.new)
    dir = File.expand_path(intent_dir)
    h = home_for(dir, home: home)
    key = resolve_session(session, store: store_for(dir), intent_id: intent_id_for(dir))
    actions = []

    if Lock.corrupt?(dir)
      File.delete(Lock.path(dir))
      actions << "removed corrupt delivery.lock"
    end

    lock = Lock.read(dir)
    if lock && !Lock.authorized?(lock, key)
      if Lock.fresh?(dir, now: now)
        return { "status" => "held", "owner" => lock["owner_session"],
                 "actions" => actions, "session" => key }
      end
      return { "status" => "stale", "owner" => lock["owner_session"],
               "actions" => actions, "session" => key,
               "hint" => "run #{Lock.skill_ref('plastic-doctor', harness: hint_harness || harness)} " \
                         "reclaim the lock to take over with an audit" }
    end

    mode = blank?(run_mode) ? (lock && lock["run_mode"]) : run_mode.to_s
    if lock
      if lock["owner_session"].to_s == key.to_s
        lock_data = lock.dup
        { "owner_harness" => harness, "owner_agent" => agent, "owner_model" => model,
          "owner_thread" => thread, "run_mode" => mode }.each do |field, value|
          lock_data[field] = value.to_s unless blank?(value)
        end
        Lock.write(dir, lock_data)
        Lock.heartbeat(dir, session: key, now: now)
      else
        Lock.heartbeat(dir, session: key, now: now)
        lock_data = Lock.read(dir)
      end
      role = lock_data["owner_session"].to_s == key.to_s ? "owner" : "delegate"
      actions << "lock kept (#{role})"
    else
      status, lock_data = Lock.acquire(dir, session: key, now: now, harness: harness,
                                       agent: agent, model: model, thread: thread,
                                       run_mode: mode)
      actions << "lock #{status}"
    end

    begin
      Worktree.provision(bridge_hash(intent_dir: dir, home: h, with_worktree: false), home: h, runner: runner)
    rescue StandardError => e
      warn "plastic: worktree provision raised during repair, continuing unprovisioned: #{e.message}"
    end
    actions << "worktree #{worktree_block(intent_dir: dir, home: h)['provisioned'] ? 'present' : 'absent'}"
    actions << "stage #{Savepoint.derive_stage(dir)}"

    { "status" => "repaired", "actions" => actions, "lock" => lock_data, "session" => key }
  end

  # The intent directory this session's pointer names, searched in the given
  # stores in order; nil when the pointer is absent, empty, or a day id.
  def intent_dir_from_pointer(session, home:, stores:)
    current = read_pointer(session, home: home)
    return nil if blank?(current) || SessionLedger.valid_day_id?(current)
    stores.each do |store|
      match = Dir.glob(File.join(store, "#{current}--*")).find { |p| File.directory?(p) }
      return match if match
    end
    nil
  end
end
