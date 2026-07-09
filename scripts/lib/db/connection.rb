# encoding: UTF-8
# frozen_string_literal: true

module Plastic
  module DB
    # Thin wrapper around SQLite3::Database. Opens a store's plastic.db and
    # applies the mandatory write-discipline PRAGMAs (D1) on open. Holds no
    # transaction of its own; Plastic::DB.with_write owns transaction scope.
    class Connection
      # D1's mandatory floor: production callers must never go below this.
      # busy_timeout: below is a DI seam (tests only -- see Plastic::DB.connect)
      # so contention-simulating tests can inject a small value instead of
      # waiting out the real production timeout on every retry.
      DEFAULT_BUSY_TIMEOUT_MS = 5000

      # journal_mode/synchronous/foreign_keys run AFTER busy_timeout is set
      # (below); busy_timeout itself is applied FIRST, load-bearing order: the
      # one-time journal_mode=WAL conversion (a write) must itself honor the
      # busy timeout, so a concurrent writer holding the file during that
      # conversion is retried instead of raising SQLITE_BUSY immediately.
      PRAGMAS = %w[
        journal_mode=WAL
        synchronous=NORMAL
        foreign_keys=ON
      ].freeze

      attr_reader :raw

      def self.open(db_path, sqlite3_module: ::SQLite3, busy_timeout: DEFAULT_BUSY_TIMEOUT_MS)
        raw = sqlite3_module::Database.new(db_path)
        raw.execute("PRAGMA busy_timeout=#{busy_timeout.to_i}")
        PRAGMAS.each { |pragma| raw.execute("PRAGMA #{pragma}") }
        new(raw)
      end

      def initialize(raw)
        @raw = raw
      end

      def execute(sql, *params)
        raw.execute(sql, *params)
      end

      def transaction(mode, &block)
        raw.transaction(mode, &block)
      end

      # Reads back a single PRAGMA value, e.g. pragma("journal_mode") => "wal".
      def pragma(name)
        row = raw.execute("PRAGMA #{name}").first
        row && row.first
      end

      def close
        raw.close unless raw.closed?
      end

      def closed?
        raw.closed?
      end
    end
  end
end
