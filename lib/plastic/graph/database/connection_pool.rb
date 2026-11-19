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

        def self.open(path, attach: {})
          FileUtils.mkdir_p(File.dirname(path))
          connection = new(path, results_as_hash: true)
          connection.foreign_keys = true
          connection.busy_timeout = BUSY_TIMEOUT
          connection.attach_all(path, attach) unless attach.empty?
          connection
        rescue Database::JournalModeRefused
          connection.close
          raise
        end

        # Attaches each file not yet attached under its schema name, then keeps its schema in a delete journal with full
        # synchronous. A new file is made with incremental auto vacuum; an existing one gets it from the VACUUM after a migration.
        def attach_all(main, files)
          pending = files.except(*attached)
          return if pending.empty?

          pending.each { |schema, file| execute("ATTACH DATABASE ? AS #{schema}", [file]).tap { attached << schema } }
          { main: main, **pending }.each { |schema, file| keep_store_modes(schema, file) }
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

        # Runs the block in one transaction that takes no lock until its first write.
        def deferred(&) = transaction_active? ? savepoint(&) : deferring(&)

        private

        def attached = (@attached ||= [])

        # Asking on an existing file would take its write lock at every connection, so only a file with no page yet asks.
        def vacuum_new_file(schema)
          execute("PRAGMA #{schema}.auto_vacuum = INCREMENTAL") if get_first_value("PRAGMA #{schema}.page_count").zero?
        end

        def keep_store_modes(schema, file)
          vacuum_new_file(schema)
          mode = get_first_value("PRAGMA #{schema}.journal_mode")
          mode = get_first_value("PRAGMA #{schema}.journal_mode = DELETE") unless mode == "wal"
          raise Database::JournalModeRefused, "#{File.basename(file)} is in #{mode} journal mode; a store keeps every file in delete mode" unless mode == "delete"

          execute("PRAGMA #{schema}.synchronous = FULL")
        end

        def deferring(&)
          execute("BEGIN DEFERRED TRANSACTION")
          undoing("ROLLBACK TRANSACTION") { yield.tap { execute("COMMIT TRANSACTION") } }
        end

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
        # A connection opened plain gains the files of a later call that attaches them, so one connection serves every caller of the path.
        def self.for(path, attach: {})
          (connections[path] ||= connect(path, attach)).tap { |connection| attach_missing(connection, path, attach) }
        end

        # The database files this process made, by full path; a file that was on the disk before is not one.
        def self.created = (@created ||= [])

        # Removes the database files this process made under the `folder`, with their journals, and forgets them.
        def self.remove_created(folder)
          made = created.select { |path| path.start_with?(folder) }
          @created = created - made
          made.uniq.product(["", "-wal", "-shm", "-journal"]).map(&:join).select { |file| File.file?(file) }.each { |file| File.delete(file) }
        end

        def self.connect(path, attach)
          remember_missing([path, *attach.values])
          Connection.open(path, attach:)
        end
        private_class_method :connect

        def self.attach_missing(connection, path, attach)
          return if attach.empty?

          remember_missing(attach.values)
          connection.attach_all(path, attach)
        end
        private_class_method :attach_missing

        def self.remember_missing(files) = files.each { |file| created << File.expand_path(file) unless File.exist?(file) }
        private_class_method :remember_missing

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
