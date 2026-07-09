# encoding: UTF-8
# frozen_string_literal: true

module Plastic
  module DB
    # DDL for every operational + derived table (D9, AC9): Rails-shaped
    # (integer id PK, created_at/updated_at TEXT ISO8601) and dialect-clean
    # (INTEGER/TEXT/REAL only, no STRICT, no WITHOUT ROWID, no engine-specific
    # extensions), so a sqlite-vec load or a Turso migration needs zero schema
    # change. ensure! is the only migration path in v1: idempotent
    # CREATE-IF-NOT-EXISTS. A format_version bump signals a cold rebuild of
    # derived tables (ACTION_8), never an ALTER here.
    module Schema
      module_function

      FORMAT_VERSION = 1

      # SQLite's built-in PRAGMA user_version, used purely as a cheap "has
      # this DB file's DDL already been applied" marker so connect() can skip
      # ensure!'s with_write (BEGIN IMMEDIATE) entirely on the overwhelmingly
      # common already-current case: a pure read or a no-op lease renewal
      # must never take the write lock just to re-run CREATE TABLE IF NOT
      # EXISTS statements it already ran. Bump only when TABLE_DDL/INDEX_DDL
      # actually changes. Unrelated to FORMAT_VERSION (schema_meta), which
      # governs Mirror's derived-table cold-rebuild trigger, a different
      # concept entirely: DDL_VERSION is about whether the DDL has run once;
      # FORMAT_VERSION is about whether the derived rows need rebuilding.
      DDL_VERSION = 1

      TABLE_DDL = [
        <<~SQL,
          CREATE TABLE IF NOT EXISTS intents (
            id INTEGER PRIMARY KEY,
            intent_id TEXT UNIQUE,
            title TEXT,
            slug TEXT,
            tags TEXT,
            author TEXT,
            created TEXT,
            chain TEXT,
            sources TEXT,
            content_hash TEXT,
            status TEXT,
            quadrant TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS edges (
            id INTEGER PRIMARY KEY,
            source_intent_id INTEGER REFERENCES intents(id),
            target_ref TEXT,
            target_intent_id INTEGER REFERENCES intents(id),
            kind TEXT,
            position INTEGER,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS savepoint_events (
            id INTEGER PRIMARY KEY,
            intent_id INTEGER REFERENCES intents(id),
            stage TEXT,
            event_type TEXT,
            actor_session TEXT,
            payload TEXT,
            occurred_at TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS lock_leases (
            id INTEGER PRIMARY KEY,
            intent_id TEXT,
            artifact TEXT,
            owner_session TEXT,
            host TEXT,
            acquired_at TEXT,
            expires_at TEXT,
            released_at TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS lock_lease_delegates (
            id INTEGER PRIMARY KEY,
            lock_lease_id INTEGER REFERENCES lock_leases(id),
            delegate_session TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY,
            session_id TEXT UNIQUE,
            host TEXT,
            pid INTEGER,
            cwd TEXT,
            active_intent_id TEXT,
            auto INTEGER,
            armed_at TEXT,
            last_seen_at TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS roadmaps (
            id INTEGER PRIMARY KEY,
            slug TEXT UNIQUE,
            title TEXT,
            goal TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS roadmap_entries (
            id INTEGER PRIMARY KEY,
            roadmap_id INTEGER REFERENCES roadmaps(id),
            intent_id TEXT,
            batch_number INTEGER,
            status TEXT,
            position INTEGER,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
        <<~SQL,
          CREATE TABLE IF NOT EXISTS schema_meta (
            id INTEGER PRIMARY KEY,
            format_version INTEGER,
            last_full_rebuild_at TEXT,
            last_reconcile_at TEXT,
            created_at TEXT,
            updated_at TEXT
          )
        SQL
      ].freeze

      INDEX_DDL = [
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_intents_intent_id ON intents(intent_id)",
        "CREATE INDEX IF NOT EXISTS idx_intents_status ON intents(status)",
        "CREATE INDEX IF NOT EXISTS idx_intents_quadrant ON intents(quadrant)",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_lock_leases_live_holder " \
          "ON lock_leases(intent_id, artifact) WHERE released_at IS NULL",
        "CREATE INDEX IF NOT EXISTS idx_lock_lease_delegates_lease_id " \
          "ON lock_lease_delegates(lock_lease_id)",
        "CREATE INDEX IF NOT EXISTS idx_savepoint_events_intent_id ON savepoint_events(intent_id)",
        "CREATE INDEX IF NOT EXISTS idx_edges_source_intent_id ON edges(source_intent_id)",
        "CREATE INDEX IF NOT EXISTS idx_roadmap_entries_roadmap_batch " \
          "ON roadmap_entries(roadmap_id, batch_number)",
      ].freeze

      # Idempotent, and a fast no-op on every connect after the first: reads
      # PRAGMA user_version (a plain read, no write lock) and skips the DDL
      # batch entirely once it already matches DDL_VERSION. Only a fresh or
      # legacy DB file (user_version not yet current) pays for the one-time
      # migration transaction, which stamps user_version at the end so every
      # later connect takes the fast path.
      def ensure!(conn, now: -> { Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ") })
        return true if current?(conn)

        Plastic::DB.with_write(conn) do |c|
          TABLE_DDL.each { |stmt| c.execute(stmt) }
          INDEX_DDL.each { |stmt| c.execute(stmt) }
          seed_schema_meta(c, now: now)
          c.execute("PRAGMA user_version = #{DDL_VERSION}")
        end
      end

      # Has this connection's DB file already had DDL_VERSION's DDL applied?
      def current?(conn)
        conn.pragma("user_version").to_i == DDL_VERSION
      end

      def rebuild_needed?(conn, code_version: FORMAT_VERSION)
        row = conn.execute("SELECT format_version FROM schema_meta WHERE id = 1").first
        stored = row && row.first
        stored != code_version
      end

      def seed_schema_meta(conn, now:)
        count = conn.execute("SELECT COUNT(*) FROM schema_meta").first.first
        return unless count.zero?

        stamp = now.call
        conn.execute(
          "INSERT INTO schema_meta (id, format_version, last_full_rebuild_at, last_reconcile_at, created_at, updated_at) " \
          "VALUES (1, ?, NULL, NULL, ?, ?)",
          [FORMAT_VERSION, stamp, stamp]
        )
      end
    end
  end
end
