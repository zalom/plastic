# frozen_string_literal: true

require "fileutils"
# The launcher starts Ruby with --disable-gems, so the kernel loads RubyGems
# itself. The require does nothing when RubyGems is already loaded.
require "rubygems"
require "sqlite3"
require_relative "../sql"

module Plastic
  module Graph
    # One SQLite file and the connection that reads and writes it.
    class Database
      # One open database file, through the sqlite3 gem: rows come back as
      # hashes, foreign keys are on, and a busy file is waited on.
      class Connection < SQLite3::Database
        BUSY_TIMEOUT = 5000

        def self.open(path)
          FileUtils.mkdir_p(File.dirname(path))
          new(path, results_as_hash: true).tap do |connection|
            connection.foreign_keys = true
            connection.busy_timeout = BUSY_TIMEOUT
          end
        end

        def read(sql, values = {})
          prepare(sql) do |statement|
            raise Plastic::Invalid, "the text must hold one statement" unless statement.remainder.strip.empty?

            statement.bind_params(SQL.params(sql, values))
            build_result_set(statement).to_a.freeze
          end
        end

        # Runs the block in one transaction that takes the write lock first.
        # Inside an open transaction, such as a test's, it is a savepoint.
        def atomically(&) = transaction_active? ? savepoint(&) : immediately(&)

        private

        def immediately(&)
          execute("BEGIN IMMEDIATE TRANSACTION")
          undoing("ROLLBACK TRANSACTION") { yield.tap { execute("COMMIT TRANSACTION") } }
        end

        def savepoint(&)
          execute("SAVEPOINT batch")
          undoing("ROLLBACK TO batch; RELEASE batch;") { yield.tap { execute("RELEASE batch") } }
        end

        def undoing(statements)
          finished = false
          result = yield
          finished = true
          result
        ensure
          execute_batch(statements) unless finished || !transaction_active?
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

        # Closes the connections of every database file under the `prefix` folder.
        def self.release(prefix)
          folder = File.join(prefix, "")
          connections.keys.select { |path| path.start_with?(folder) }.each { |path| connections.delete(path).close }
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
