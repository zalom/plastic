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

  TYPES = %w[delivery maintenance].freeze

  # Lease TTL. Heartbeats fire from the write-path hooks (PostToolUse
  # gate-check and the lock-gate allow path), so a delivering session
  # refreshes constantly; 30 minutes tolerates long read-only stretches
  # without opening a takeover window mid-delivery. Reclaim is explicit
  # either way (takeover), so the TTL only bounds WHEN takeover is allowed.
  TTL_SECONDS = 1800

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
              ttl: TTL_SECONDS, now: Time.now)
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
        data = payload(session: session, type: type, host: host, now: now,
                       delegates: Array(existing["delegates"]))
        write(intent_dir, data, type: type)
        return [:owned, data]
      end
      return [:held, existing] if fresh?(intent_dir, type: type, ttl: ttl, now: now)
      return [:stale, existing]
    end

    data = payload(session: session, type: type, host: host, now: now)
    File.open(path(intent_dir, type: type),
              File::WRONLY | File::CREAT | File::EXCL) do |io|
      io.write(JSON.pretty_generate(data))
    end
    [:acquired, data]
  rescue Errno::EEXIST
    [:held, read(intent_dir, type: type)] # lost the O_EXCL race
  end

  def payload(session:, type:, host:, now:, delegates: [])
    {
      "type" => type,
      "owner_session" => session.to_s,
      "host" => host,
      "acquired_at" => now.utc.iso8601,
      "delegates" => delegates,
    }
  end

  # Owner/delegate heartbeat: touch the mtime, never rewrite content.
  def heartbeat(intent_dir, session:, type: "delivery", now: Time.now)
    return false unless holds?(intent_dir, session: session, type: type)
    FileUtils.touch(path(intent_dir, type: type), mtime: now)
    true
  end

  # Owner registers a delegate (D4): a session allowed to write under this
  # lock. Only the OWNER may delegate; delegates cannot re-delegate.
  def add_delegate(intent_dir, delegate:, session:, type: "delivery")
    data = read(intent_dir, type: type)
    return false if blank?(delegate)
    return false unless data && data["owner_session"].to_s == session.to_s
    data["delegates"] = (Array(data["delegates"]) + [delegate.to_s]).uniq
    write(intent_dir, data, type: type)
    true
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
               ttl: TTL_SECONDS, now: Time.now)
    existing = read(intent_dir, type: type)
    if existing && !authorized?(existing, session) &&
       fresh?(intent_dir, type: type, ttl: ttl, now: now)
      return [:fresh, existing]
    end

    old_owner = existing ? existing["owner_session"] : "corrupt-or-missing"
    p = path(intent_dir, type: type)
    File.delete(p) if File.exist?(p)
    status, data = acquire(intent_dir, session: session, type: type, host: host,
                           ttl: ttl, now: now)
    return [status, data] unless status == :acquired

    audit = "#{now.utc.iso8601}  Lock  takeover: #{session} reclaimed #{type} " \
            "lock from #{old_owner}\n"
    File.open(File.join(intent_dir, "savepoint.md"), "a") { |io| io.write(audit) }
    [:taken, data]
  end

  # Rewrite the lock file in place (owner-side mutations). A content write also
  # refreshes the mtime, which is correct: every sanctioned mutation is owner
  # activity.
  def write(intent_dir, data, type: "delivery")
    File.write(path(intent_dir, type: type), JSON.pretty_generate(data))
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
  def claim_gate_reason(intent_dir, artifact, session:, ttl: Lock::TTL_SECONDS, now: Time.now)
    return nil if Lock.blank?(artifact)
    return nil unless File.exist?(path(intent_dir, artifact))   # dormant: no claim
    return nil if holds_claim?(intent_dir, artifact, session: session)  # you hold it
    return nil if fail_open?(intent_dir, artifact, ttl: ttl, now: now)  # stale/corrupt: yield
    data = read(intent_dir, artifact)
    holder = data && data["owner_session"]
    since = data && data["acquired_at"]
    "artifact #{artifact} is claimed by #{holder} since #{since}; another writer holds " \
      "it. Back off or run /plastic-doctor check the lock status. If you are a distinct " \
      "delegate, the owner must register you: plastic-lock delegate --intent-dir " \
      "#{intent_dir} --session <your-session-id>"
  end
end
