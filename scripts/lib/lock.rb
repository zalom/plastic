# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "fileutils"
require "socket"
require "time"

# Lock: the durable single-owner delivery lock (intent 108).
#
# One JSON lock file per intent, delivery.lock, living IN the intent dir beside
# savepoint.md (git-ignored, transient state). Ownership is session-keyed (D1):
# the file records the owner session, never a pid. Liveness is a lease: the
# owner's hooks touch the file mtime on tool calls (heartbeat); the lock is
# stale only when that heartbeat is older than the TTL. The /tmp bridge is a
# per-session CACHE of this state; on any disagreement the lock file wins (D2).
#
# Mutual-exclusion seam (D3): the schema carries a type ("delivery" now,
# "maintenance" in a chained intent after 93) and acquire refuses while the
# OTHER type is fresh. Only the seam ships in 108.
#
# Pure and dependency-injected: every function takes explicit paths plus ttl:
# and now:; nothing here reads ENV or globals, and nothing shells out.
module Lock
  module_function

  # Skill-invocation prefix per harness (intent 201, D2/D3). Claude Code invokes a
  # skill with a slash (/plastic-doctor); Codex CLI invokes explicitly with a
  # dollar ($plastic-doctor) and may also select one implicitly by matching the
  # skill's description. This table is the actual source of truth for
  # Bridge.skill_ref (bridge.rb requires lock.rb, never the reverse, so the
  # table lives here rather than pulling Bridge into this dependency-free file
  # just to render two characters). InstallerCore::DEFAULT_AGENTS carries the
  # same values per adapter as documented config (see ACTION_2); this constant
  # is not read from it at runtime, by the same reasoning bridge.rb/hook-*
  # already stay clear of installer_core.rb (spec Alternatives Considered).
  SKILL_PREFIXES = { "claude" => "/", "codex" => "$" }.freeze

  # Renders a skill reference for the given harness. Unset or unrecognized
  # harness falls back to Claude's slash form, so an existing call site that
  # never passes harness: keeps behaving exactly as it does today (D2). name
  # is the bare skill name ("plastic-doctor"), never pre-prefixed.
  def self.skill_ref(name, harness: :claude)
    prefix = SKILL_PREFIXES.fetch(harness.to_s, SKILL_PREFIXES["claude"])
    "#{prefix}#{name}"
  end

  TYPES = %w[delivery maintenance].freeze
  DELEGATE_ACTIVITY_LIMIT = 20
  DELEGATE_STATUSES = %w[active finished failed].freeze

  # Lease TTL. Heartbeats fire from the write-path hooks (PostToolUse
  # gate-check and the lock-gate allow path), so a delivering session
  # refreshes constantly; 30 minutes tolerates long read-only stretches
  # without opening a takeover window mid-delivery. Reclaim is explicit
  # either way (takeover), so the TTL only bounds WHEN takeover is allowed.
  TTL_SECONDS = 1800

  # The write guard is a mutex, not a lock in the Plastic sense: it carries no
  # owner, no timestamp, and no content, it is only an inode to flock. It is
  # a SIBLING of delivery.lock (never delivery.lock itself), because renaming
  # over a file you hold an flock on leaves you holding an orphaned inode
  # while the next writer flocks a fresh one at the same path. The name lands
  # inside the existing *.lock rule in ~/.plastic/.gitignore, so no gitignore
  # change is needed.
  WRITE_GUARD_TIMEOUT_SECONDS = 2.0
  WRITE_GUARD_RETRY_SECONDS = 0.01

  # The sibling guard path for a lock type. NOT built by passing a compound
  # type: into path (see TYPES comment above): Lock.path(dir, type:
  # "delivery.write") would render the same string, and the exclusion at
  # acquire ((TYPES - [type]).first) silently checks only one other type, so
  # a third TYPES entry would break mutual exclusion with no error. This
  # helper keeps the guard entirely outside TYPES.
  def write_guard_path(intent_dir, type: "delivery")
    File.join(intent_dir, "#{type}.write.lock")
  end

  # The sibling temp path for write's write-to-temp-then-rename. Ends in
  # ".lock" (not just ".tmp") so a temp orphaned by a crash between the
  # write and the rename is covered by the store's existing *.lock
  # .gitignore rule rather than committed by the store's `git add -A`
  # auto-commit. Sibling in the same directory as the target, never a
  # system tmpdir, because File.rename can raise EXDEV across filesystems.
  def write_temp_path(intent_dir, type: "delivery")
    "#{path(intent_dir, type: type)}.tmp.#{Process.pid}.#{Thread.current.object_id}." \
      "#{Time.now.to_f}.lock"
  end

  def blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  def path(intent_dir, type: "delivery")
    File.join(intent_dir, "#{type}.lock")
  end

  # Parsed lock Hash, or nil when absent or corrupt (corrupt? distinguishes).
  def read(intent_dir, type: "delivery")
    p = path(intent_dir, type: type)
    return nil unless File.exist?(p)
    data = JSON.parse(File.read(p)) rescue nil
    data.is_a?(Hash) ? data : nil
  end

  def corrupt?(intent_dir, type: "delivery")
    File.exist?(path(intent_dir, type: type)) && read(intent_dir, type: type).nil?
  end

  # Lease freshness: the file mtime IS the heartbeat.
  def fresh?(intent_dir, type: "delivery", ttl: TTL_SECONDS, now: Time.now)
    p = path(intent_dir, type: type)
    return false unless File.exist?(p)
    (now - File.mtime(p)) <= ttl
  end

  # session is the owner or a registered delegate (D4).
  def authorized?(data, session)
    return false unless data.is_a?(Hash)
    return false if blank?(session)
    return true if data["owner_session"].to_s == session.to_s
    Array(data["delegates"]).map(&:to_s).include?(session.to_s)
  end

  # The one question gates ask: does session hold this intent's lock?
  # Owner/delegate on an EXISTING lock counts even when stale (a stale lock is
  # still theirs until an explicit takeover replaces it); freshness only
  # guards AGAINST other sessions.
  def holds?(intent_dir, session:, type: "delivery")
    authorized?(read(intent_dir, type: type), session)
  end

  # Atomic acquisition (O_EXCL). Returns a [status, data] pair:
  #   [:acquired, lock]  created fresh
  #   [:owned, lock]     re-acquire by the current owner (idempotent re-arm)
  #   [:held, lock]      fresh foreign lock: back off
  #   [:stale, lock]     expired foreign lock: explicit takeover required
  #   [:excluded, other] the OTHER lock type is fresh (D3)
  #   [:corrupt, nil]    unparseable lock file: run repair
  def acquire(intent_dir, session:, type: "delivery", host: Socket.gethostname,
              ttl: TTL_SECONDS, now: Time.now, harness: nil, agent: nil,
              model: nil, thread: nil, run_mode: nil)
    raise ArgumentError, "unknown lock type #{type.inspect}" unless TYPES.include?(type)
    raise ArgumentError, "lock session must be present" if blank?(session)

    other = (TYPES - [type]).first
    if fresh?(intent_dir, type: other, ttl: ttl, now: now)
      return [:excluded, read(intent_dir, type: other)]
    end

    return [:corrupt, nil] if corrupt?(intent_dir, type: type)

    existing = read(intent_dir, type: type)
    if existing
      if existing["owner_session"].to_s == session.to_s
        # Re-read happens INSIDE the guard so the read-modify-write is
        # covered, not just the write (spec D5). Fall back to the
        # already-read existing when the file has vanished underneath us.
        # If the re-read shows a different owner, keep today's outcome and
        # write anyway: an owner-changed-underneath refusal would be new
        # semantics the spec does not authorize. The rebuilt payload then
        # carries THIS session as owner while inheriting the NEW owner's
        # delegate list, merging two lock identities into one record. The
        # window is a takeover landing between the pre-guard read and the
        # guarded re-read; no test covers it, and closing it means guarding
        # takeover itself, which this intent's scope does not authorize.
        data = with_write_guard(intent_dir, type: type) do
          record = read(intent_dir, type: type) || existing
          rebuilt = payload(session: session, type: type, host: host, now: now,
                            delegates: Array(record["delegates"]),
                            delegate_activity: Array(record["delegate_activity"]),
                            harness: merged_value(harness, record["owner_harness"]),
                            agent: merged_value(agent, record["owner_agent"]),
                            model: merged_value(model, record["owner_model"]),
                            thread: merged_value(thread, record["owner_thread"]),
                            run_mode: merged_value(run_mode, record["run_mode"]))
          write(intent_dir, rebuilt, type: type)
          rebuilt
        end
        return [:owned, data]
      end
      return [:held, existing] if fresh?(intent_dir, type: type, ttl: ttl, now: now)
      return [:stale, existing]
    end

    data = payload(session: session, type: type, host: host, now: now,
                   harness: harness, agent: agent, model: model, thread: thread,
                   run_mode: run_mode)
    File.open(path(intent_dir, type: type),
              File::WRONLY | File::CREAT | File::EXCL) do |io|
      io.write(JSON.pretty_generate(data))
    end
    [:acquired, data]
  rescue Errno::EEXIST
    [:held, read(intent_dir, type: type)] # lost the O_EXCL race
  end

  def payload(session:, type:, host:, now:, delegates: [], delegate_activity: [],
              harness: nil, agent: nil, model: nil, thread: nil, run_mode: nil)
    {
      "type" => type,
      "owner_session" => session.to_s,
      "host" => host,
      "acquired_at" => now.utc.iso8601,
      "delegates" => delegates,
      "owner_harness" => normalized_value(harness),
      "owner_agent" => normalized_value(agent),
      "owner_model" => normalized_value(model),
      "owner_thread" => normalized_value(thread),
      "run_mode" => normalized_value(run_mode),
      "delegate_activity" => bounded_delegate_activity(delegate_activity, delegates: delegates),
    }
  end

  def normalized_value(value)
    blank?(value) ? nil : value.to_s
  end

  def merged_value(explicit, existing)
    blank?(explicit) ? normalized_value(existing) : explicit.to_s
  end

  # Keep every active record that still names an authorized delegate, while
  # bounding completed history. Active work is current truth and must never be
  # evicted merely because newer delegates finished.
  def bounded_delegate_activity(records, delegates:)
    records = Array(records)
    authorized = Array(delegates).map(&:to_s)
    terminal_indexes = records.each_index.reject do |index|
      record = records[index]
      record.is_a?(Hash) && record["status"].to_s == "active" &&
        authorized.include?(record["session"].to_s)
    end.last(DELEGATE_ACTIVITY_LIMIT)
    records.each_with_index.filter_map do |record, index|
      active = record.is_a?(Hash) && record["status"].to_s == "active" &&
               authorized.include?(record["session"].to_s)
      record if active || terminal_indexes.include?(index)
    end
  end

  # Owner/delegate heartbeat: touch the mtime, never rewrite content.
  def heartbeat(intent_dir, session:, type: "delivery", now: Time.now)
    return false unless holds?(intent_dir, session: session, type: type)
    FileUtils.touch(path(intent_dir, type: type), mtime: now)
    true
  end

  # Owner registers a delegate (D4): a session allowed to write under this
  # lock. Only the OWNER may delegate; delegates cannot re-delegate.
  def add_delegate(intent_dir, delegate:, session:, type: "delivery", now: Time.now,
                   harness: nil, agent: nil, model: nil, thread: nil)
    return false if blank?(delegate)
    # The read moves inside the guard (spec D5): a guard around the write
    # alone still loses updates, since both writers already read the stale
    # copy before contending for the guard.
    with_write_guard(intent_dir, type: type) do
      data = read(intent_dir, type: type)
      next false unless data && data["owner_session"].to_s == session.to_s
      data["delegates"] = (Array(data["delegates"]) + [delegate.to_s]).uniq
      activity = Array(data["delegate_activity"])
      previous = activity.find { |record| record.is_a?(Hash) && record["session"].to_s == delegate.to_s }
      activity.reject! { |record| record.is_a?(Hash) && record["session"].to_s == delegate.to_s }
      record = {
        "session" => delegate.to_s,
        "status" => "active",
        "registered_at" => now.utc.iso8601,
        "last_activity_at" => now.utc.iso8601,
        "harness" => merged_value(harness, previous && previous["harness"]),
        "agent" => merged_value(agent, previous && previous["agent"]),
        "model" => merged_value(model, previous && previous["model"]),
        "thread" => merged_value(thread, previous && previous["thread"]),
      }
      data["delegate_activity"] = bounded_delegate_activity(activity + [record],
                                                            delegates: data["delegates"])
      write(intent_dir, data, type: type)
      true
    end
  end

  # Activity metadata is observational only. Finishing or failing a delegate
  # never removes its string session id from the authorization list.
  def update_delegate_status(intent_dir, delegate:, status:, session:, type: "delivery",
                             now: Time.now)
    return false unless (DELEGATE_STATUSES - ["active"]).include?(status.to_s)
    with_write_guard(intent_dir, type: type) do
      data = read(intent_dir, type: type)
      next false unless data && data["owner_session"].to_s == session.to_s
      activity = Array(data["delegate_activity"])
      index = activity.index do |record|
        record.is_a?(Hash) && record["session"].to_s == delegate.to_s
      end
      next false unless index
      activity[index] = activity[index].merge(
        "status" => status.to_s,
        "last_activity_at" => now.utc.iso8601
      )
      data["delegate_activity"] = bounded_delegate_activity(activity,
                                                            delegates: data["delegates"])
      write(intent_dir, data, type: type)
      true
    end
  end

  # Owner releases the lock (disarm / End tail, D6). force: true is the repair
  # path's escape hatch for corrupt or own-session rebuilds.
  # Returns :released, :not_owner, or :none.
  def release(intent_dir, session:, type: "delivery", force: false)
    p = path(intent_dir, type: type)
    return :none unless File.exist?(p)
    data = read(intent_dir, type: type)
    unless force || (data && data["owner_session"].to_s == session.to_s)
      return :not_owner
    end
    File.delete(p)
    :released
  end

  # Explicit takeover of a stale (or corrupt) lock (D2): replace the lock and
  # append an audit line to savepoint.md. NEVER takes over a fresh foreign
  # lock; there is no silent reclaim path anywhere else.
  # Returns [:taken, data], [:fresh, existing], or acquire's error statuses.
  def takeover(intent_dir, session:, type: "delivery", host: Socket.gethostname,
               ttl: TTL_SECONDS, now: Time.now, harness: nil, agent: nil,
               model: nil, thread: nil, run_mode: nil)
    existing = read(intent_dir, type: type)
    if existing && !authorized?(existing, session) &&
       fresh?(intent_dir, type: type, ttl: ttl, now: now)
      return [:fresh, existing]
    end

    old_owner = existing ? existing["owner_session"] : "corrupt-or-missing"
    p = path(intent_dir, type: type)
    File.delete(p) if File.exist?(p)
    status, data = acquire(intent_dir, session: session, type: type, host: host,
                           ttl: ttl, now: now, harness: harness, agent: agent,
                           model: model, thread: thread, run_mode: run_mode)
    return [status, data] unless status == :acquired

    audit = "#{now.utc.iso8601}  Lock  takeover: #{session} reclaimed #{type} " \
            "lock from #{old_owner}\n"
    File.open(File.join(intent_dir, "savepoint.md"), "a") { |io| io.write(audit) }
    [:taken, data]
  end

  # Bounded mutual exclusion for the read-modify-write callers of write (spec
  # D3, D5): acquire's re-acquire branch, add_delegate, and
  # update_delegate_status each read, modify, then write, and the guard must
  # span the whole sequence, not just the write, or two writers that already
  # read the stale copy before contending still lose an update.
  #
  # NOT re-entrant: it opens a fresh file descriptor on every call, and flock
  # is scoped to the open file description, so a nested acquisition from the
  # same process would conflict with its own outer hold and burn the whole
  # timeout budget on every single write. write must never take this guard
  # itself; only the three read-modify-write call sites do.
  #
  # Fails open on every edge, per Plastic's fail-open doctrine (intent 93 D7,
  # 111, 112): when the guard file cannot be opened, and when the flock
  # cannot be won inside guard_timeout, the block still runs and its value is
  # still returned. The write still happens, still atomically; the worst case
  # on timeout is exactly today's possibly-lost update, never a torn file and
  # never a hang.
  #
  # The guard file must never be deleted, by anyone, ever. Unlinking an
  # flock target is the unlink-recreate race: a later opener would create a
  # fresh inode and stop serializing against the current holder, breaking
  # mutual exclusion exactly when contention is highest. scripts/write-config:59
  # leaves config.yml.lock in place for the same reason. A leftover guard
  # file is inert: nothing reads it, it stays zero bytes, and
  # scripts/end-intent:558 keys its exit contract on Lock.path alone. This is
  # a requirement, not a guarantee the code enforces: the curator stray-file
  # rule (skills/conventions/references/maintenance-and-revisions.md:155)
  # has no *.lock carve-out today, so a wrongful delete there degrades one
  # write window to the pre-fix (unguarded) behavior, not a hard failure.
  def with_write_guard(intent_dir, type: "delivery",
                       guard_timeout: WRITE_GUARD_TIMEOUT_SECONDS,
                       guard_retry: WRITE_GUARD_RETRY_SECONDS)
    handle = begin
      File.open(write_guard_path(intent_dir, type: type), File::CREAT | File::RDWR, 0o644)
    rescue SystemCallError
      nil
    end
    return yield unless handle

    begin
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + guard_timeout
      begin
        until handle.flock(File::LOCK_EX | File::LOCK_NB)
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          sleep guard_retry
        end
      rescue SystemCallError
        # File#flock RAISES (does not return false) for every errno except
        # EWOULDBLOCK, so on a filesystem where flock is unsupported (NFS,
        # SMB, some FUSE mounts) this loop raises instead of just failing to
        # win the lock. An flock we cannot take must degrade to an
        # unguarded but still atomic write, same as the File.open rescue
        # above, or this method breaks its own fail-open promise.
        nil
      end
      yield
    ensure
      begin
        handle.flock(File::LOCK_UN)
      rescue SystemCallError
        nil
      end
      begin
        handle.close
      rescue SystemCallError, IOError
        nil
      end
    end
  end

  # Rewrite the lock file in place (owner-side mutations): write-to-sibling-
  # temp plus File.rename, never an in-place truncate. POSIX rename is an
  # atomic replace, so a concurrent reader always observes either the
  # complete previous content or the complete new content, never a partial
  # file. The temp file is a SIBLING in the same directory as the target,
  # never a system tmpdir, because File.rename can raise EXDEV when the temp
  # and the target live on different filesystems.
  #
  # A content write also refreshes the mtime, which is correct: every
  # sanctioned mutation is owner activity. File.rename carries the temp
  # file's mtime onto the target, so the post-rename mtime is "now", exactly
  # what fresh? (above) and the hook heartbeats already assume. The rename
  # also swaps the inode, which is safe here: heartbeat touches by path
  # through FileUtils.touch, not by handle, and nothing in the repo holds an
  # open handle on delivery.lock across a write.
  #
  # This method does NOT take the write guard itself. with_write_guard is not
  # re-entrant, so a nested acquisition from the same process would conflict
  # with its own outer hold and burn the entire timeout budget on every
  # write, including the hot heartbeat path. The three read-modify-write
  # callers take the guard around the whole sequence instead; write stays a
  # bare atomic replace.
  def write(intent_dir, data, type: "delivery")
    target = path(intent_dir, type: type)
    temp = write_temp_path(intent_dir, type: type)
    File.write(temp, JSON.pretty_generate(data))
    File.rename(temp, target)
  rescue StandardError
    File.delete(temp) if temp && File.exist?(temp)
    raise
  end

  # Read-only normalized inspection. The lock file and its mtime remain the
  # sole sources of owner and heartbeat truth; no environment or transcript
  # inference belongs here.
  def who(intent_dir, ttl: TTL_SECONDS, now: Time.now)
    p = path(intent_dir)
    unless File.exist?(p)
      return { "state" => "none",
               "claims" => Claim.claims_status(intent_dir, ttl: ttl, now: now) }
    end
    data = read(intent_dir)
    unless data
      return { "state" => "corrupt",
               "claims" => Claim.claims_status(intent_dir, ttl: ttl, now: now) }
    end

    activity = Array(data["delegate_activity"])
    activity_by_session = activity.each_with_object({}) do |record, memo|
      memo[record["session"].to_s] = record if record.is_a?(Hash)
    end
    authorized_sessions = Array(data["delegates"]).map(&:to_s)
    activity_sessions = activity.filter_map do |record|
      record["session"].to_s if record.is_a?(Hash) &&
                                authorized_sessions.include?(record["session"].to_s)
    end.uniq
    activity_order = activity.each_with_index.each_with_object({}) do |(record, index), memo|
      memo[record["session"].to_s] = index if record.is_a?(Hash)
    end
    activity_sessions.sort_by! do |session|
      record = activity_by_session[session] || {}
      # Active delegates are current ahead of terminal delegates. Within that
      # group, latest activity wins; original record order is the stable
      # fallback for legacy records without timestamps.
      [record["status"].to_s == "active" ? 1 : 0,
       record["last_activity_at"].to_s, activity_order.fetch(session, -1)]
    end
    # Legacy string-only delegates retain their authorization order. Rich
    # records follow in deterministic current/latest order, so consumers may
    # reliably take the last projection entry: the most recent active delegate
    # when one exists, otherwise the most recent terminal activity.
    ordered_sessions = (authorized_sessions - activity_sessions) + activity_sessions
    delegates = ordered_sessions.map do |session|
      record = activity_by_session[session] || {}
      {
        "session" => session,
        "harness" => normalized_value(record["harness"]) || "unknown",
        "agent" => normalized_value(record["agent"]) || "unknown",
        "model" => normalized_value(record["model"]) || "unknown",
        "thread" => normalized_value(record["thread"]) || "unknown",
        "status" => normalized_value(record["status"]) || "unknown",
        "registered_at" => record["registered_at"],
        "last_activity_at" => record["last_activity_at"],
      }
    end
    {
      "state" => fresh?(intent_dir, ttl: ttl, now: now) ? "fresh" : "stale",
      "owner" => {
        "harness" => normalized_value(data["owner_harness"]) || "unknown",
        "agent" => normalized_value(data["owner_agent"]) || "unknown",
        "model" => normalized_value(data["owner_model"]) || "unknown",
        "thread" => normalized_value(data["owner_thread"]) || "unknown",
        "run_mode" => normalized_value(data["run_mode"]) || "unknown",
      },
      "owner_session" => data["owner_session"],
      "heartbeat_at" => File.mtime(p).utc.iso8601,
      "delegates" => delegates,
      "claims" => Claim.claims_status(intent_dir, ttl: ttl, now: now),
    }
  end
end

# Claim: the per-artifact claim-token layer (intent 111, D1/D7). Sits BENEATH
# the session-keyed delivery lock: a lifecycle-file write must hold BOTH the
# intent's delivery lock (Lock, unchanged) AND that specific artifact's claim.
# Neither layer replaces the other.
#
# Storage: one small JSON file per artifact, sibling to delivery.lock, under
# `.claims/<artifact>.claim` INSIDE the intent dir. Scope is strictly
# per-intent-per-artifact (D4, hard constraint): a claim's on-disk path is
# always `<intent_dir>/.claims/<artifact>.claim`, so a claim can never affect
# any artifact but its own, nor any intent but its own. This is what stops a
# stuck/stale claim from recreating the collision-90 failure mode.
#
# Exclusivity is O_EXCL at acquire, not session-equality (see plan.md): a
# fresh claim is NEVER idempotently re-granted, even to the session that
# holds it. This is what makes "exactly one writer" mechanical rather than a
# convention: the second acquire against a live claim is rejected at the
# filesystem, even when both callers share one CLAUDE_CODE_SESSION_ID.
#
# Fail open, always (D3): a stale or corrupt claim never blocks; it yields to
# the current writer and the condition is surfaced (see Claim.fail_open?,
# added in a later action, the named contract 112 gates on).
#
# Pure and dependency-injected: every function takes explicit paths plus ttl:
# and now:; nothing here reads ENV or globals, and nothing shells out. Does
# not touch any Lock function.
module Claim
  module_function

  CLAIMS_DIR = ".claims"

  def dir_path(intent_dir)
    File.join(intent_dir, CLAIMS_DIR)
  end

  def path(intent_dir, artifact)
    File.join(dir_path(intent_dir), "#{artifact}.claim")
  end

  # Parsed claim Hash, or nil when absent or corrupt (corrupt? distinguishes).
  def read(intent_dir, artifact)
    p = path(intent_dir, artifact)
    return nil unless File.exist?(p)
    data = JSON.parse(File.read(p)) rescue nil
    data.is_a?(Hash) ? data : nil
  end

  def corrupt?(intent_dir, artifact)
    File.exist?(path(intent_dir, artifact)) && read(intent_dir, artifact).nil?
  end

  # Lease freshness: the file mtime IS the heartbeat (mirrors Lock.fresh?).
  def fresh?(intent_dir, artifact, ttl: Lock::TTL_SECONDS, now: Time.now)
    p = path(intent_dir, artifact)
    return false unless File.exist?(p)
    (now - File.mtime(p)) <= ttl
  end

  def payload(session:, artifact:, now:, delegate: nil)
    {
      "artifact" => artifact,
      "owner_session" => session.to_s,
      "acquired_at" => now.utc.iso8601,
      "delegate" => delegate,
    }
  end

  # Atomic acquisition (O_EXCL). Returns a [status, data] pair:
  #   [:acquired, claim]  created fresh
  #   [:held, claim]      fresh claim (own or foreign): never idempotently
  #                       re-granted; the caller backs off or waits
  #   [:stale, claim]     expired claim: caller may take over (see plastic-lock)
  #   [:corrupt, nil]     unparseable claim file: caller may repair
  def acquire_claim(intent_dir, artifact, session:, delegate: nil,
                     ttl: Lock::TTL_SECONDS, now: Time.now)
    raise ArgumentError, "claim session must be present" if Lock.blank?(session)
    raise ArgumentError, "claim artifact must be present" if Lock.blank?(artifact)

    FileUtils.mkdir_p(dir_path(intent_dir))
    return [:corrupt, nil] if corrupt?(intent_dir, artifact)

    existing = read(intent_dir, artifact)
    if existing
      return [:held, existing] if fresh?(intent_dir, artifact, ttl: ttl, now: now)
      return [:stale, existing]
    end

    data = payload(session: session, artifact: artifact, now: now, delegate: delegate)
    File.open(path(intent_dir, artifact),
              File::WRONLY | File::CREAT | File::EXCL) do |io|
      io.write(JSON.pretty_generate(data))
    end
    [:acquired, data]
  rescue Errno::EEXIST
    [:held, read(intent_dir, artifact)] # lost the O_EXCL race
  end

  # session is the owner or the registered delegate on this claim. Stale-own
  # still counts as holding (mirrors Lock.holds?): the claim is theirs until
  # an explicit takeover replaces it; freshness only guards AGAINST others.
  def holds_claim?(intent_dir, artifact, session:)
    data = read(intent_dir, artifact)
    return false unless data.is_a?(Hash)
    return false if Lock.blank?(session)
    data["owner_session"].to_s == session.to_s || data["delegate"].to_s == session.to_s
  end

  # Owner (or force:) releases the claim. Returns :none, :not_owner, or
  # :released.
  def release_claim(intent_dir, artifact, session:, force: false)
    p = path(intent_dir, artifact)
    return :none unless File.exist?(p)
    unless force || holds_claim?(intent_dir, artifact, session: session)
      return :not_owner
    end
    File.delete(p)
    :released
  end

  # Owner/delegate heartbeat: touch the mtime, never rewrite content. False
  # (no-op) when the session does not hold the claim.
  def heartbeat(intent_dir, artifact, session:, now: Time.now)
    return false unless holds_claim?(intent_dir, artifact, session: session)
    FileUtils.touch(path(intent_dir, artifact), mtime: now)
    true
  end

  # The named fail-open contract (intent 111 D6; intent 112 gates its Exec on
  # this test and re-runs it as a regression check on every lock.rb edit it
  # makes). True iff a claim FILE exists but is unresolvable (stale or
  # corrupt): the write must PROCEED (yield the claim to the current writer)
  # and surface the condition; it MUST NEVER block. Absence of a claim is not
  # fail-open, that is plain dormancy (the gate is not engaged at all).
  def fail_open?(intent_dir, artifact, ttl: Lock::TTL_SECONDS, now: Time.now)
    return true if corrupt?(intent_dir, artifact)
    !!(read(intent_dir, artifact) && !fresh?(intent_dir, artifact, ttl: ttl, now: now))
  end

  # The data behind `plastic-lock status` (AC5): every live claim under this
  # intent, with enough to show who holds what since when, and whether it is
  # still fresh. Returns [] when no artifact has ever been claimed.
  def claims_status(intent_dir, ttl: Lock::TTL_SECONDS, now: Time.now)
    return [] unless Dir.exist?(dir_path(intent_dir))
    Dir.glob(File.join(dir_path(intent_dir), "*.claim")).sort.map do |file|
      artifact = File.basename(file, ".claim")
      data = begin
        parsed = JSON.parse(File.read(file))
        parsed.is_a?(Hash) ? parsed : nil
      rescue JSON::ParserError
        nil
      end
      {
        "artifact" => (data && data["artifact"]) || artifact,
        "owner_session" => data && data["owner_session"],
        "delegate" => data && data["delegate"],
        "acquired_at" => data && data["acquired_at"],
        "fresh" => fresh?(intent_dir, artifact, ttl: ttl, now: now),
        "corrupt" => data.nil?,
      }
    end
  end

  # Second, independent write gate at the artifact grain (intent 111 D7). Returns a
  # deny reason String to BLOCK, or nil to ALLOW. Composes UNDER the delivery-lock
  # gate: only reached after the session already holds the intent's delivery lock.
  # ENGAGES only when a claim file exists (dormant otherwise, so single-owner flows
  # and the existing suite stay green, AC7). Fails open on stale/corrupt via
  # fail_open?, the named contract.
  def claim_gate_reason(intent_dir, artifact, session:, ttl: Lock::TTL_SECONDS, now: Time.now,
                        harness: :claude)
    return nil if Lock.blank?(artifact)
    return nil unless File.exist?(path(intent_dir, artifact))   # dormant: no claim
    return nil if holds_claim?(intent_dir, artifact, session: session)  # you hold it
    return nil if fail_open?(intent_dir, artifact, ttl: ttl, now: now)  # stale/corrupt: yield
    data = read(intent_dir, artifact)
    holder = data && data["owner_session"]
    since = data && data["acquired_at"]
    "artifact #{artifact} is claimed by #{holder} since #{since}; another writer holds " \
      "it. Back off or run #{Lock.skill_ref('plastic-doctor', harness: harness)} check the " \
      "lock status. If you are a distinct delegate, the owner must register you: " \
      "plastic-lock delegate --intent-dir #{intent_dir} --session <your-session-id>"
  end
end
