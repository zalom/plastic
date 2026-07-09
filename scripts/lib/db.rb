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
  end
end
