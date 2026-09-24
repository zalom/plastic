# encoding: UTF-8
# frozen_string_literal: true

require_relative "store_layout"
require "digest"
require "fileutils"
require_relative "lock"
require_relative "worktree"
require_relative "session_ledger"
require_relative "savepoint"

# Arm - how an auto team takes an intent and gives it back (intent 307).
#
# Two durable facts make a delivery: the delivery lock in the intent
# directory says who delivers, and the code worktree under the project repo
# says where the code lands. A conversation session's tmp directory under
# the global store's `.tmp/` says only that a session started; it names no
# intent. This module carries the
# arm, disarm, and repair operations (intent 307); the pure INDEX/project-config
# helpers that once sat alongside them on a shared-helpers module now live on
# IndexEntry and ProjectConfig (intent 344).
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
  # for headless runs that carry no session id at all.
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
    Plastic::StoreLayout.global_store(File.join(File.expand_path(home), ".plastic"))
  end

  # The minimal hash Worktree.provision, release, and finish consume: the
  # intent block plus, when asked, the derived worktree block.
  def delivery(intent_dir:, home: Dir.home, with_worktree: true)
    dir = File.expand_path(intent_dir)
    data = {
      "intent" => { "id" => intent_id_for(dir), "dir" => File.basename(dir), "store" => store_for(dir) },
    }
    data["worktree"] = worktree_block(intent_dir: dir, home: home) if with_worktree
    data
  end

  # `{code, code_branch, provisioned}` derived from projects.yml and the
  # intent id: the workspace the agent is told to create (Plastic runs no
  # `git worktree add` itself, intent 390). `code`/`code_branch` name the
  # expected path and branch whenever a repo resolves for the project, blank
  # only for a store-only (non-git) intent; `provisioned` alone says whether
  # that directory already exists on disk.
  def worktree_block(intent_dir:, home: Dir.home)
    p = code_paths(intent_dir: intent_dir, home: home)
    code = p["code"]
    provisioned = !blank?(code) && Dir.exist?(code)
    {
      "code" => code,
      "code_branch" => code ? p["code_branch"] : nil,
      "provisioned" => provisioned,
    }
  end

  # The code worktree path and branch this intent would have, whether or not
  # the worktree exists on disk (blank code for a store-only project).
  def code_paths(intent_dir:, home: Dir.home)
    dir = File.expand_path(intent_dir)
    h = home_for(dir, home: home)
    slug = Worktree.slug_for_store(store_for(dir), home: h)
    Worktree.paths(slug: slug, intent_id: intent_id_for(dir),
                   intent_slug: Worktree.slug_from_dir(dir), home: h)
  end

  # Owner rule 2026-08-31: has this session already started a conversation?
  # A conversation session's tmp directory is made at boot under the global
  # store's `.tmp/`; a dispatched or headless session (a derived key) never
  # gets one. Reads only; rescues to false (fail open: a broken store must
  # never block a legitimate delivery).
  def started_session?(session, home:)
    store = global_store(home)
    Dir.exist?(SessionLedger.session_tmp_dir(store, SessionLedger.short_session_id(nil, session)))
  rescue StandardError
    false
  end

  # --- arm ---------------------------------------------------------------------

  # Take an intent for `session`: acquire delivery.lock (stamped with the run
  # mode and the provenance the caller knows) and provision the code worktree
  # (fail-open for a global-only or non-git intent). Returns
  # `{status:, lock:, worktree:, session:}`. A held, stale, excluded, or
  # corrupt lock returns that status with the lock data read and touches
  # nothing.
  def arm(intent_dir:, session:, mode: "auto", home: Dir.home, harness: nil,
          agent: nil, model: nil, thread: nil, now: Time.now, runner: Worktree::ShellRunner.new,
          host: Socket.gethostname, allow_inline: false)
    raise ArgumentError, "mode must be auto or guided" unless %w[auto guided].include?(mode.to_s)
    dir = File.expand_path(intent_dir)
    key = resolve_session(session, store: store_for(dir), intent_id: intent_id_for(dir))
    h = home_for(dir, home: home)

    # Owner rule 2026-08-31: the main session never delivers an intent inline.
    # A conversation session (its tmp directory already exists under the
    # global store) arming an intent it does not already hold the lock for is
    # inline delivery and is refused BEFORE any lock is taken. Re-arming the
    # intent it already holds stays idempotent. A dispatched or headless
    # session has no tmp directory and arms freely. --allow-inline is the
    # explicit owner override.
    if !allow_inline && started_session?(key, home: h) && !Lock.holds?(dir, session: key)
      return { status: :inline_refused, lock: nil, worktree: nil, session: key }
    end

    status, lock = Lock.acquire(dir, session: key, host: host, now: now,
                                harness: harness, agent: agent, model: model,
                                thread: thread, run_mode: mode.to_s)
    unless %i[acquired owned].include?(status)
      return { status: status, lock: lock, worktree: nil, session: key }
    end

    { status: status, lock: lock, worktree: worktree_block(intent_dir: dir, home: h),
      session: key }
  end

  # --- disarm ------------------------------------------------------------------

  # Give the intent back: remove the worktree (when `remove`) and release the
  # lock as its recorded owner (falling back to `session`). Returns the lock
  # release status (:released, :none, :not_owner, or :raised).
  def disarm(intent_dir:, session:, home: Dir.home, runner: Worktree::ShellRunner.new,
             remove: true, now: Time.now)
    dir = File.expand_path(intent_dir)
    h = home_for(dir, home: home)
    key = resolve_session(session, store: store_for(dir), intent_id: intent_id_for(dir))

    begin
      Worktree.release(delivery(intent_dir: dir, home: h), home: h, runner: runner, remove: remove)
    rescue StandardError => e
      warn "plastic: worktree release raised, continuing: #{e.message}"
    end

    lock = Lock.read(dir)
    owner = lock && !blank?(lock["owner_session"]) ? lock["owner_session"] : key
    begin
      Lock.release(dir, session: owner)
    rescue StandardError => e
      warn "plastic: delivery lock release raised for #{dir}, continuing: #{e.message}"
      :raised
    end
  end

  # --- repair ------------------------------------------------------------------

  # A stale foreign lock is reclaimed only by an audited owner step, never by
  # the session that found it.
  def stale_hint(intent_id)
    "reclaiming a stale lock is the owner's audited step; plastic auto lock status #{intent_id} shows it"
  end

  # One idempotent repair (the lock half of the repair path):
  # remove a corrupt lock, back off from a fresh foreign lock (`held`), report
  # a stale foreign lock (`stale`) for the explicit reclaim verb, keep and
  # enrich an own lock, heartbeat a delegated one, acquire when none, and
  # report whether the repaired intent's workspace is present. Plastic
  # creates no worktree here (intent 390); the agent is told to.
  def repair(intent_dir:, session:, home: Dir.home, now: Time.now, harness: nil,
             agent: nil, model: nil, thread: nil, run_mode: nil,
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
               "hint" => stale_hint(intent_id_for(dir)) }
    end

    # A lock rebuilt from nothing (none, or a corrupt one removed) is an auto
    # delivery's lock again; a kept lock keeps whatever mode it had.
    mode = if !blank?(run_mode)
      run_mode.to_s
    elsif lock
      lock["run_mode"]
    else
      "auto"
    end
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

    actions << "worktree #{worktree_block(intent_dir: dir, home: h)['provisioned'] ? 'present' : 'absent'}"
    actions << "stage #{Savepoint.derive_stage(dir)}"

    { "status" => "repaired", "actions" => actions, "lock" => lock_data, "session" => key }
  end
end
