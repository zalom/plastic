# encoding: UTF-8
# frozen_string_literal: true

module Plastic
  module DB
    # Plastic::DB::Sessions — the `sessions` table (D-migration-spine, intent
    # 41 ACTION_4). Replaces the /tmp bridge's session cache: one row per
    # armed session, register/update/end verbs, active-for-cwd resolution
    # (intent 131 parity), and `to_bridge_data`, the adapter that turns a
    # session row into the SAME Hash shape `Bridge.discover_bridge` returns
    # today so the unchanged gate-decision functions
    # (`code_gate_decision`/`worktree_gate_decision`/`lock_gate_decision`)
    # consume DB state through their existing interface (ACTION_9 rewires the
    # callers onto this; this action only builds the read/write surface).
    #
    # Session-id convention: a single real/derived session can legitimately
    # own SEVERAL concurrently-armed intents (one per auto delivery), the
    # same fact that drove the old bridge's per-intent-keyed filename
    # `plastic-<session>--<intent_id>.json`. Because `sessions.session_id` is
    # UNIQUE (one row per key, not one row per bare session), a per-intent
    # row's `session_id` is stored as `"<bare_session>--<intent_id>"`,
    # mirroring that filename exactly; a caller with no concurrent intents
    # keeps using the bare form. `active_for`'s session filter and
    # `to_bridge_data`'s `bare_session` both understand this convention.
    module Sessions
      COLUMNS = %w[
        session_id host pid cwd active_intent_id auto armed_at last_seen_at
        created_at updated_at
      ].freeze

      ALLOWED_UPDATE_FIELDS = %i[cwd active_intent_id auto].freeze

      class << self
        def register(conn, session_id:, host:, pid:, cwd:, active_intent_id:, auto:, now:)
          return nil if conn.nil?

          stamp = iso(now)
          Plastic::DB.with_write(conn) do |c|
            c.execute(
              "INSERT INTO sessions (session_id, host, pid, cwd, active_intent_id, auto, " \
              "armed_at, last_seen_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " \
              "ON CONFLICT(session_id) DO UPDATE SET " \
              "host = excluded.host, pid = excluded.pid, cwd = excluded.cwd, " \
              "active_intent_id = excluded.active_intent_id, auto = excluded.auto, " \
              "last_seen_at = excluded.last_seen_at, updated_at = excluded.updated_at",
              [session_id, host, pid, cwd, active_intent_id, bool_int(auto), stamp, stamp, stamp, stamp]
            )
            find_row(c, session_id)
          end
        end

        def update(conn, session_id:, now:, **fields)
          return nil if conn.nil?

          patch = fields.slice(*ALLOWED_UPDATE_FIELDS)
          Plastic::DB.with_write(conn) do |c|
            return nil if find_row(c, session_id).nil?

            stamp = iso(now)
            assignments = patch.keys.map { |k| "#{k} = ?" } + ["last_seen_at = ?", "updated_at = ?"]
            values = patch.map { |k, v| k == :auto ? bool_int(v) : v }
            values.concat([stamp, stamp, session_id])
            c.execute("UPDATE sessions SET #{assignments.join(', ')} WHERE session_id = ?", values)
            find_row(c, session_id)
          end
        end

        # Named `end` per the spec (delete/tombstone the row); defined via
        # define_method because `end` is a reserved word and cannot follow
        # `def`. Callable exactly like any other module method: `Sessions.end(...)`.
        define_method(:end) do |conn, session_id:|
          return nil if conn.nil?

          Plastic::DB.with_write(conn) do |c|
            c.execute("DELETE FROM sessions WHERE session_id = ?", [session_id])
            session_id
          end
        end

        # Resolve THE session row a gate should act on, mirroring
        # `discover_bridge`'s tiering. `session` given: strict ownership,
        # scoped to that bare session's own row family (never a foreign
        # session's row). `cwd` then disambiguates between siblings by
        # overlap with each row's own `cwd` (the strongest available signal,
        # analogous to the old worktree.code tier); off-cwd falls back to
        # auto-preference, then newest `last_seen_at`.
        def active_for(conn, session:, cwd:)
          return nil if conn.nil?

          rows = all_rows(conn)
          return nil if rows.empty?

          unless blank?(session)
            rows = rows.select { |r| own_session_row?(r, session) }
            return nil if rows.empty?
          end

          cwd_abs = blank?(cwd) ? nil : File.expand_path(cwd)
          if cwd_abs
            overlapping = rows.select { |r| cwd_overlap?(r["cwd"], cwd_abs) }
            return pick_preferred(overlapping) if overlapping.any?
          end

          pick_preferred(rows)
        end

        # Thin read join to `lock_leases` (the only cross-table access this
        # module makes; ACTION_3 owns writes to that table). Returns the
        # live delivery-grain lease row (artifact IS NULL, not yet released)
        # for intent_id, or nil.
        def current_lock_row(conn, intent_id)
          return nil if conn.nil? || blank?(intent_id)

          cols = %w[owner_session host acquired_at artifact expires_at released_at]
          row = conn.execute(
            "SELECT #{cols.join(', ')} FROM lock_leases " \
            "WHERE intent_id = ? AND artifact IS NULL AND released_at IS NULL " \
            "ORDER BY acquired_at DESC LIMIT 1",
            [intent_id]
          ).first
          row && cols.zip(row).to_h
        end

        # Build the SAME Hash shape `Bridge.discover_bridge` returns today,
        # from a session row (+ optional joined lock_leases row), so the
        # unchanged gate-decision functions read it verbatim. Pure: no conn,
        # no I/O.
        def to_bridge_data(row, intent_dir:, lock_row: nil)
          return nil if row.nil?

          active_intent_id = row["active_intent_id"]
          store = intent_dir ? File.dirname(intent_dir) : nil
          dir = intent_dir ? File.basename(intent_dir) : nil
          cwd = row["cwd"]

          {
            "session" => bare_session(row["session_id"], active_intent_id),
            "intent" => {
              "id" => active_intent_id,
              "store" => store,
              "dir" => dir,
            },
            "build" => {
              "auto" => row["auto"].to_i == 1,
            },
            "worktree" => {
              "code" => cwd,
              "code_branch" => nil,
              "store" => store,
              "store_branch" => nil,
              "provisioned" => !blank?(cwd),
            },
            "lock" => lock_cache_from(lock_row),
          }
        end

        private

        def blank?(value)
          value.nil? || value.to_s.strip.empty?
        end

        def bool_int(value)
          value ? 1 : 0
        end

        def iso(now)
          now.utc.iso8601
        end

        def row_to_hash(values)
          COLUMNS.zip(values).to_h
        end

        def find_row(conn, session_id)
          row = conn.execute(
            "SELECT #{COLUMNS.join(', ')} FROM sessions WHERE session_id = ?", [session_id]
          ).first
          row && row_to_hash(row)
        end

        def all_rows(conn)
          conn.execute("SELECT #{COLUMNS.join(', ')} FROM sessions").map { |row| row_to_hash(row) }
        end

        # A row belongs to `session` when its key is either the bare session
        # (legacy/no-concurrent-intent form) or one of that session's
        # per-intent rows (`"<session>--<intent_id>"`).
        def own_session_row?(row, session)
          sid = row["session_id"].to_s
          sid == session.to_s || sid.start_with?("#{session}--")
        end

        def cwd_overlap?(row_cwd, cwd_abs)
          return false if blank?(row_cwd)

          rc = File.expand_path(row_cwd)
          cwd_abs == rc || cwd_abs.start_with?("#{rc}/")
        end

        def pick_preferred(rows)
          return nil if rows.empty?

          auto_rows = rows.select { |r| r["auto"].to_i == 1 }
          pool = auto_rows.empty? ? rows : auto_rows
          pool.max_by { |r| r["last_seen_at"].to_s }
        end

        # Strip the `--<active_intent_id>` suffix a per-intent row's key
        # carries, recovering the bare session id `Bridge` expects in
        # bridge_data["session"] (the JSON content's "session" field was
        # always the bare key, even for per-intent-keyed files).
        def bare_session(session_id, active_intent_id)
          sid = session_id.to_s
          return sid if blank?(active_intent_id)

          suffix = "--#{active_intent_id}"
          sid.end_with?(suffix) ? sid[0...-suffix.length] : sid
        end

        def lock_cache_from(lock_row)
          if lock_row.nil?
            return { "owner_session" => nil, "acquired_at" => nil, "host" => nil,
                     "type" => nil, "delegates" => [] }
          end

          {
            "owner_session" => lock_row["owner_session"],
            "acquired_at" => lock_row["acquired_at"],
            "host" => lock_row["host"],
            "type" => blank?(lock_row["artifact"]) ? "delivery" : "artifact",
            "delegates" => [],
          }
        end
      end
    end
  end
end
