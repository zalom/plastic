# encoding: UTF-8
# frozen_string_literal: true

require "time"
require_relative "../db"

module Plastic
  module DB
    # Leases: lock_leases rows replace the file-based Lock (delivery.lock) and
    # Claim (.claims/*.claim) layers from intent 41 (D8) onward. A lease IS one
    # atomically-written row; there is no filename-vs-content pair to drift out
    # of sync, so the name/content-mismatch bug class (131/136) cannot exist
    # here by construction.
    #
    # Grain: `artifact IS NULL` is the delivery grain (mirrors Lock); a non-NULL
    # `artifact` is a per-artifact claim (mirrors Claim). Both grains share one
    # table and one set of verbs below; callers pick the grain via `artifact:`.
    #
    # Atomicity note (load-bearing, do not "simplify" away): SQLite considers
    # every NULL distinct from every other NULL for UNIQUE index purposes, so
    # the partial unique index on (intent_id, artifact) WHERE released_at IS
    # NULL does NOT by itself stop two concurrent live rows at the delivery
    # grain (artifact IS NULL) -- verified empirically against sqlite3 before
    # writing this file. The real mutual exclusion is the check-then-insert
    # done ENTIRELY inside one `with_write` (BEGIN IMMEDIATE) transaction: only
    # one writer holds the RESERVED lock at a time, so "is there a live row?"
    # and "insert the new live row" happen as one atomic step regardless of
    # NULL semantics. The unique index remains a belt-and-suspenders backstop
    # for the non-NULL artifact grain (and any bug in the check-then-insert
    # path), so `acquire`/`takeover` still rescue SQLite3::ConstraintException.
    #
    # Fail open, always: a nil `conn` (no sqlite3 gem, unopenable DB) makes
    # every verb below return its fail-open result immediately and never
    # raise. Expiry is also fail-open by construction: an expired live row
    # never blocks `gate_reason`/`claim_gate_reason`, it simply yields.
    module Leases
      module_function

      # Mirrors Lock::TTL_SECONDS (30 minutes): generous enough that a
      # delivering session's normal read/write cadence never lets its own
      # lease expire out from under it.
      TTL_SECONDS = 1800

      # Renew is coarse and off the hot path (Notes: "leases are leases, not
      # per-heartbeat writes"): only bump expires_at once the remaining life
      # is inside this window, so a caller may call renew on every tool
      # activity without turning it into a write on every call.
      RENEW_WINDOW_SECONDS = 300

      COLUMNS = %w[
        id intent_id artifact owner_session host acquired_at expires_at
        released_at created_at updated_at
      ].freeze

      SELECT_COLUMNS_SQL = COLUMNS.join(", ")

      # Atomic acquire (D8 core verb). Returns a [status, row] pair:
      #   [:acquired, row]   created fresh, no live row existed
      #   [:owned, row]      re-acquire by the current owner_session (idempotent,
      #                      also refreshes expires_at/host)
      #   [:held, row]       a fresh foreign live row exists: back off
      #   [:stale, row]      a foreign live row exists but is expired: caller
      #                      may `takeover`
      #   [:fail_open, nil]  conn is nil (no DB): caller must ALLOW
      def acquire(conn, intent_id, artifact: nil, session:, host:, ttl: TTL_SECONDS, now: Time.now)
        result = Plastic::DB.with_write(conn) do |c|
          existing = find_live(c, intent_id, artifact)

          if existing
            if existing["owner_session"] == session.to_s
              stamp = iso(now)
              c.execute(
                "UPDATE lock_leases SET expires_at = ?, host = ?, updated_at = ? WHERE id = ?",
                [iso(now + ttl), host, stamp, existing["id"]]
              )
              next [:owned, find_live(c, intent_id, artifact)]
            end

            next [:held, existing] if fresh_row?(existing, now: now)
            next [:stale, existing]
          end

          insert_live_row(c, intent_id, artifact, session, host, ttl, now)
        end

        result.nil? ? [:fail_open, nil] : result
      end

      # Coarse renewal: bumps expires_at ONLY when the remaining life is
      # inside renew_window. Returns :renewed, :not_due (no-op, not yet time),
      # :not_owner, :none (no live row), or :fail_open (nil conn).
      def renew(conn, intent_id, artifact: nil, session:, ttl: TTL_SECONDS,
                renew_window: RENEW_WINDOW_SECONDS, now: Time.now)
        result = Plastic::DB.with_write(conn) do |c|
          existing = find_live(c, intent_id, artifact)
          next :none unless existing
          next :not_owner unless existing["owner_session"] == session.to_s

          exp = parse_time(existing["expires_at"])
          next :not_due if exp && (exp - now) > renew_window

          stamp = iso(now)
          c.execute(
            "UPDATE lock_leases SET expires_at = ?, updated_at = ? WHERE id = ?",
            [iso(now + ttl), stamp, existing["id"]]
          )
          :renewed
        end

        result.nil? ? :fail_open : result
      end

      # Owner releases the lease (sets released_at). Returns :released,
      # :not_owner, :none, or :fail_open (nil conn).
      def release(conn, intent_id, artifact: nil, session:, now: Time.now)
        result = Plastic::DB.with_write(conn) do |c|
          existing = find_live(c, intent_id, artifact)
          next :none unless existing
          next :not_owner unless existing["owner_session"] == session.to_s

          stamp = iso(now)
          c.execute(
            "UPDATE lock_leases SET released_at = ?, updated_at = ? WHERE id = ?",
            [stamp, stamp, existing["id"]]
          )
          :released
        end

        result.nil? ? :fail_open : result
      end

      # Explicit takeover of an expired or absent live row (mirrors
      # Lock.takeover). NEVER replaces a fresh foreign row: [:fresh, existing].
      # On success: [:taken, row]. [:fail_open, nil] on a nil conn.
      def takeover(conn, intent_id, artifact: nil, session:, host:, ttl: TTL_SECONDS, now: Time.now)
        result = Plastic::DB.with_write(conn) do |c|
          existing = find_live(c, intent_id, artifact)
          if existing && existing["owner_session"] != session.to_s && fresh_row?(existing, now: now)
            next [:fresh, existing]
          end

          if existing
            stamp = iso(now)
            c.execute(
              "UPDATE lock_leases SET released_at = ?, updated_at = ? WHERE id = ?",
              [stamp, stamp, existing["id"]]
            )
          end

          status, row = insert_live_row(c, intent_id, artifact, session, host, ttl, now)
          status == :acquired ? [:taken, row] : [status, row]
        end

        result.nil? ? [:fail_open, nil] : result
      end

      # Does `session` hold a live lease for this grain? Stale-own still
      # counts (mirrors Lock.holds?): the lease is theirs until an explicit
      # takeover replaces it. Read-only; false (never raises) on a nil conn.
      def holds?(conn, intent_id, artifact: nil, session:)
        return false if conn.nil?

        row = find_live(conn, intent_id, artifact)
        !!(row && row["owner_session"] == session.to_s)
      end

      # Is there a live AND unexpired row for this grain? Read-only; false on
      # a nil conn.
      def fresh?(conn, intent_id, artifact: nil, now: Time.now)
        return false if conn.nil?

        fresh_row?(find_live(conn, intent_id, artifact), now: now)
      end

      # Delivery-grain write gate (artifact always NULL). Returns a deny
      # String to BLOCK, or nil to ALLOW: dormant (no lease) -> nil; you hold
      # it -> nil; fresh foreign holder -> deny naming holder + since;
      # expired foreign holder -> nil (fail-open, expiry always yields). nil
      # conn -> nil (fail-open: no DB, no gate).
      def gate_reason(conn, intent_id, session:, now: Time.now)
        return nil if conn.nil?

        row = find_live(conn, intent_id, nil)
        return nil unless row
        return nil if row["owner_session"] == session.to_s
        return nil unless fresh_row?(row, now: now)

        "intent #{intent_id} delivery is held by #{row['owner_session']} since " \
          "#{row['acquired_at']}; another writer holds it. Back off or take over " \
          "via Plastic::DB::Leases.takeover."
      end

      # Artifact-grain write gate. Same contract shape as gate_reason, scoped
      # to one artifact; dormant (nil) when artifact is blank or unclaimed.
      def claim_gate_reason(conn, intent_id, artifact, session:, now: Time.now)
        return nil if conn.nil?
        return nil if artifact.nil? || artifact.to_s.strip.empty?

        row = find_live(conn, intent_id, artifact)
        return nil unless row
        return nil if row["owner_session"] == session.to_s
        return nil unless fresh_row?(row, now: now)

        "artifact #{artifact} in intent #{intent_id} is claimed by #{row['owner_session']} " \
          "since #{row['acquired_at']}; another writer holds it. Back off or take over " \
          "via Plastic::DB::Leases.takeover."
      end

      # -- internal helpers -----------------------------------------------

      # Inserts a fresh live row and re-reads it. Belt-and-suspenders rescue
      # of the partial unique index for the non-NULL artifact grain (see the
      # module comment on why the delivery grain's atomicity does NOT come
      # from this index): a losing insert is re-classified exactly like an
      # existing-row race would be.
      def insert_live_row(conn, intent_id, artifact, session, host, ttl, now)
        stamp = iso(now)
        conn.execute(
          "INSERT INTO lock_leases (intent_id, artifact, owner_session, host, " \
          "acquired_at, expires_at, released_at, created_at, updated_at) " \
          "VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?)",
          [intent_id.to_s, artifact&.to_s, session.to_s, host, stamp, iso(now + ttl), stamp, stamp]
        )
        [:acquired, find_live(conn, intent_id, artifact)]
      rescue ::SQLite3::ConstraintException
        loser = find_live(conn, intent_id, artifact)
        fresh_row?(loser, now: now) ? [:held, loser] : [:stale, loser]
      end
      private_class_method :insert_live_row

      def find_live(conn, intent_id, artifact)
        if artifact.nil?
          sql = "SELECT #{SELECT_COLUMNS_SQL} FROM lock_leases " \
                "WHERE intent_id = ? AND artifact IS NULL AND released_at IS NULL"
          params = [intent_id.to_s]
        else
          sql = "SELECT #{SELECT_COLUMNS_SQL} FROM lock_leases " \
                "WHERE intent_id = ? AND artifact = ? AND released_at IS NULL"
          params = [intent_id.to_s, artifact.to_s]
        end
        to_row(conn.execute(sql, params).first)
      end
      private_class_method :find_live

      def to_row(values)
        return nil unless values

        COLUMNS.zip(values).to_h
      end
      private_class_method :to_row

      def fresh_row?(row, now:)
        return false unless row

        exp = parse_time(row["expires_at"])
        return false unless exp

        now.utc <= exp
      end
      private_class_method :fresh_row?

      def parse_time(str)
        return nil if str.nil?

        Time.parse(str).utc
      rescue ArgumentError
        nil
      end
      private_class_method :parse_time

      def iso(time)
        time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
      end
      private_class_method :iso
    end
  end
end
