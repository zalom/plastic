# encoding: UTF-8
# frozen_string_literal: true

module Plastic
  module DB
    # Thin wrapper around SQLite3::Database. Opens a store's plastic.db and
    # applies the mandatory write-discipline PRAGMAs (D1) on open. Holds no
    # transaction of its own; Plastic::DB.with_write owns transaction scope.
    class Connection
      PRAGMAS = %w[
        journal_mode=WAL
        busy_timeout=5000
        synchronous=NORMAL
        foreign_keys=ON
      ].freeze

      attr_reader :raw

      def self.open(db_path, sqlite3_module: ::SQLite3)
        raw = sqlite3_module::Database.new(db_path)
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
