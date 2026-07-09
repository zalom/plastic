# encoding: UTF-8
# frozen_string_literal: true

begin
  require "sqlite3"
  SQLITE3_AVAILABLE = true
rescue LoadError
  SQLITE3_AVAILABLE = false
end

require_relative "db/connection"
require_relative "db/store_resolver"
require_relative "db/schema"
require_relative "db/mirror"
require_relative "db/leases"
require_relative "db/sessions"
require_relative "db/savepoint_events"
require_relative "db/roadmaps"
require_relative "db/rebuild"

# Plastic::DB — the single entry point every consumer uses to talk to a
# store's plastic.db. No consumer writes SQL directly (D7); this facade plus
# the small scripts/lib/db/ package under it is the whole surface.
#
# Fails open by construction (Notes: "fail open, always"): when the sqlite3
# gem is absent or the DB file can't be opened, `connect` returns nil, and
# `with_write` treats a nil connection as a no-op returning the fail-open
# sentinel. Callers must ALLOW on a nil connection, never block.
module Plastic
  module DB
    module_function

    FAIL_OPEN_SENTINEL = nil

    def available?
      SQLITE3_AVAILABLE
    end

    # Opens (creating if absent) the plastic.db under store_home with the
    # write-discipline PRAGMAs applied. store_home is the directory holding
    # INDEX.md (global: plastic_home; project: plastic_home/projects/slug).
    #
    # available: is an injectable seam so tests can force absence without
    # unloading the gem. ensure_schema: is a DI seam for the schema-ensure
    # step, defaulting to Schema.ensure!; pass nil to skip it.
    def connect(store_home, available: available?, ensure_schema: ->(conn) { Schema.ensure!(conn) })
      return nil unless available

      db_path = StoreResolver.db_path_for_store(store_home)
      conn = begin
        Connection.open(db_path)
      rescue StandardError
        return nil
      end
      ensure_schema&.call(conn)
      conn
    end

    # Nil-safe write helper: BEGIN IMMEDIATE + a short transaction + bounded
    # SQLITE_BUSY retry (D1). A nil conn (fail-open) returns the fail-open
    # sentinel immediately and never touches the block.
    def with_write(conn, tries: 5, base_sleep: 0.05, sleeper: method(:sleep), &block)
      return FAIL_OPEN_SENTINEL if conn.nil?

      retryable(tries: tries, base_sleep: base_sleep, sleeper: sleeper) do
        result = nil
        conn.transaction(:immediate) { result = block.call(conn) }
        result
      end
    end

    # Bounded exponential backoff around SQLite busy/locked errors. Returns
    # the fail-open sentinel when the retry budget is exhausted; never loops
    # forever, never raises past the budget.
    def retryable(tries: 5, base_sleep: 0.05, sleeper: method(:sleep))
      attempt = 0
      begin
        yield
      rescue ::SQLite3::BusyException, ::SQLite3::LockedException
        attempt += 1
        if attempt >= tries
          FAIL_OPEN_SENTINEL
        else
          sleeper.call(base_sleep * (2**(attempt - 1)))
          retry
        end
      end
    end

    # ------------------------------------------------------------------
    # Query + record verb API (ACTION_7, D7/AC5): the ONLY surface any
    # consumer (agent, hook, CLI) touches. Every verb below takes `store` --
    # a store_home path, or nil to auto-resolve the caller's cwd via
    # StoreResolver -- opens its own short-lived connection through
    # `connect`, and fails open exactly like `connect`/`with_write` already
    # do: a query verb returns `[]`, a record verb returns the fail-open
    # sentinel (or the module's own fail-open token, e.g. `:fail_open` for
    # leases), and nothing ever raises past this layer.
    # ------------------------------------------------------------------

    INTENT_COLUMNS = %w[
      intent_id title slug tags author created chain sources status quadrant created_at updated_at
    ].freeze

    def store_conn(store, available:)
      home = store || StoreResolver.resolve(cwd: Dir.pwd)[:store_home]
      connect(home, available: available)
    end

    def intent_row_to_hash(row)
      INTENT_COLUMNS.zip(row).to_h
    end

    def intent_hash_for(conn, intent_id)
      row = conn.execute("SELECT #{INTENT_COLUMNS.join(', ')} FROM intents WHERE intent_id = ?", [intent_id]).first
      row && intent_row_to_hash(row)
    end

    # --- query verbs -----------------------------------------------------

    def by_status(store, status, available: available?)
      conn = store_conn(store, available: available)
      return [] if conn.nil?

      rows = conn.execute("SELECT #{INTENT_COLUMNS.join(', ')} FROM intents WHERE status = ? ORDER BY intent_id", [status])
      rows.map { |row| intent_row_to_hash(row) }
    end

    def by_quadrant(store, quadrant, available: available?)
      conn = store_conn(store, available: available)
      return [] if conn.nil?

      rows = conn.execute(
        "SELECT #{INTENT_COLUMNS.join(', ')} FROM intents WHERE quadrant = ? ORDER BY intent_id", [quadrant]
      )
      rows.map { |row| intent_row_to_hash(row) }
    end

    def by_queue(store, roadmap_slug, batch: nil, available: available?)
      conn = store_conn(store, available: available)
      return [] if conn.nil?

      Roadmaps.entries_for(conn, roadmap_slug, batch: batch)
              .filter_map { |entry| intent_hash_for(conn, entry["intent_id"]) }
    end

    # --- record verbs: authoritative status/quadrant ----------------------

    def set_status(store, intent_id, status, now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      with_write(conn) { |c| upsert_intent_column(c, intent_id, "status", status, iso(now)) }
    end

    def set_quadrant(store, intent_id, quadrant, now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      with_write(conn) { |c| upsert_intent_column(c, intent_id, "quadrant", quadrant, iso(now)) }
    end

    def upsert_intent_column(conn, intent_id, column, value, stamp)
      existing = conn.execute("SELECT id FROM intents WHERE intent_id = ?", [intent_id]).first
      if existing
        conn.execute("UPDATE intents SET #{column} = ?, updated_at = ? WHERE id = ?", [value, stamp, existing.first])
      else
        conn.execute(
          "INSERT INTO intents (intent_id, #{column}, created_at, updated_at) VALUES (?, ?, ?, ?)",
          [intent_id, value, stamp, stamp]
        )
      end
      true
    end

    # --- record verb: savepoint events + export ---------------------------

    def stamp_event(store, intent_id, stage:, event_type:, actor_session:, payload: {},
                     occurred_at: iso(Time.now), available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      SavepointEvents.stamp(conn, intent_id: intent_id, stage: stage, event_type: event_type,
                             actor_session: actor_session, occurred_at: occurred_at, payload: payload)
    end

    def export_savepoint(store, intent_id, intent_dir:, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      SavepointEvents.export(conn, intent_id: intent_id, intent_dir: intent_dir)
    end

    # --- record verbs: leases ----------------------------------------------

    def lease_acquire(store, intent_id, artifact: nil, session:, host: "unknown-host",
                       ttl: Leases::TTL_SECONDS, now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return [:fail_open, nil] if conn.nil?

      Leases.acquire(conn, intent_id, artifact: artifact, session: session, host: host, ttl: ttl, now: now)
    end

    def lease_renew(store, intent_id, artifact: nil, session:, ttl: Leases::TTL_SECONDS,
                     renew_window: Leases::RENEW_WINDOW_SECONDS, now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return :fail_open if conn.nil?

      Leases.renew(conn, intent_id, artifact: artifact, session: session, ttl: ttl, renew_window: renew_window, now: now)
    end

    def lease_release(store, intent_id, artifact: nil, session:, now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return :fail_open if conn.nil?

      Leases.release(conn, intent_id, artifact: artifact, session: session, now: now)
    end

    # --- record verbs: sessions ---------------------------------------------

    def session_register(store, session_id:, host:, pid:, cwd:, active_intent_id:, auto:,
                          now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Sessions.register(conn, session_id: session_id, host: host, pid: pid, cwd: cwd,
                         active_intent_id: active_intent_id, auto: auto, now: now)
    end

    def session_update(store, session_id:, now: Time.now, available: available?, **fields)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Sessions.update(conn, session_id: session_id, now: now, **fields)
    end

    def session_end(store, session_id:, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Sessions.end(conn, session_id: session_id)
    end

    # --- record verbs: roadmaps ----------------------------------------------

    def roadmap_upsert(store, slug:, title: nil, goal: nil, now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Roadmaps.upsert(conn, slug: slug, title: title, goal: goal, now: now)
    end

    def roadmap_entry_set(store, roadmap_slug:, intent_id:, batch_number: nil, status: nil, position: nil,
                           now: Time.now, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Roadmaps.entry_set(conn, roadmap_slug: roadmap_slug, intent_id: intent_id, batch_number: batch_number,
                          status: status, position: position, now: now)
    end

    def iso(time)
      time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end

    # --- cold rebuild (ACTION_8, AC3) ---------------------------------------

    def rebuild!(store, now: Time.now.utc, available: available?)
      home = store || StoreResolver.resolve(cwd: Dir.pwd)[:store_home]
      conn = connect(home, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Rebuild.rebuild!(conn, store_home: home, now: now)
    end

    def canonical_dump(store, available: available?)
      conn = store_conn(store, available: available)
      return FAIL_OPEN_SENTINEL if conn.nil?

      Rebuild.canonical_dump(conn)
    end
  end
end
