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
