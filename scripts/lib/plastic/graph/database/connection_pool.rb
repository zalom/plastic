# frozen_string_literal: true

require "fileutils"
# The launcher starts Ruby with --disable-gems, so the kernel loads RubyGems
# itself. The require does nothing when RubyGems is already loaded.
require "rubygems"
require "sqlite3"

module Plastic
  module Graph
    # One SQLite file and the connection that reads and writes it.
    class Database
      # One open database file, through the sqlite3 gem: rows come back as
      # hashes, foreign keys are on, and a busy file is waited on.
      class Connection < SQLite3::Database
        BUSY_TIMEOUT = 5000
        SEPARATORS = /\A[\s;]+/

        # The first statement of a script.
        class Statement < SQLite3::Statement
          # Runs, adds its rows to `found` when it gave any, closes, and returns the rest of the script.
          def run(found)
            rows = execute.to_a
            found << rows unless rows.empty?
            remainder
          ensure
            close
          end
        end

        def self.open(path)
          FileUtils.mkdir_p(File.dirname(path))
          new(path, results_as_hash: true).tap do |connection|
            connection.foreign_keys = true
            connection.busy_timeout = BUSY_TIMEOUT
          end
        end

        # The rows of each statement of `script` that gives any, in order.
        def sets(script)
          found = []
          script = Statement.new(self, script).run(found) until (script = script.sub(SEPARATORS, "")).empty?
          found
        end

        # Runs the block in one transaction that takes the write lock first.
        # Inside an open transaction, such as a test's, it is a savepoint.
        def atomically(&) = transaction_active? ? savepoint(&) : transaction(:immediate, &)

        private

        def savepoint
          execute("SAVEPOINT batch")
          yield.tap { execute("RELEASE batch") }
        rescue SQLite3::Exception
          execute_batch("ROLLBACK TO batch; RELEASE batch;")
          raise
        end
      end

      # The open connections of this Ruby process, one per database file, as
      # a Rails process keeps one connection per database. A connection opens
      # on first use and closes at exit. A forked child starts with none.
      module ConnectionPool
        def self.for(path) = connections[path] ||= Connection.open(path)

        # Closes every connection except those of the `keep` paths.
        def self.disconnect(keep: [])
          connections.except(*keep).each_value(&:close)
          connections.keep_if { |path, _connection| keep.include?(path) }
        end

        def self.connections
          pid = Process.pid
          @connections = {} unless @pid == pid
          @pid = pid
          @connections
        end
      end

      at_exit { ConnectionPool.disconnect }
    end
  end
end
