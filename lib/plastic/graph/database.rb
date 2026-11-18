# frozen_string_literal: true

require "forwardable"
require_relative "../errors"
require_relative "missing_store"
require_relative "schema"
require_relative "schema/gate"
require_relative "schema/migrator"
require_relative "schema/migration_list"
require_relative "sql"
require_relative "database/batch"
require_relative "database/connection_pool"
require_relative "database/check"
require_relative "database/tally"

module Plastic
  module Graph
    # One SQLite database through the sqlite3 gem. The rows are the authority;
    # the files are printed from them.
    #
    # A write is one transaction. BEGIN IMMEDIATE takes the write lock first,
    # so two calls that both ask for the next intent id get two ids. Inside
    # an open transaction, such as a test's, the write is a savepoint. Each
    # database counts the rows that this call wrote, and the report prints
    # the counts on its `wrote:` line.
    class Database
      extend Forwardable

      # A statement failed, or the file cannot be opened.
      class Error < Failed; end

      # Ends a dry run, which takes its statements back.
      class Undone < StandardError; end

      # The local database, for what belongs to one machine.
      def self.open_local(home) = { local: Local.new(home) }

      # The store folder under the home, which must exist.
      def self.store_root(home, store)
        root = File.join(home, "stores", store)
        raise Error, "#{home}: the plastic home is not a folder" if File.exist?(home) && !File.directory?(home)
        raise MissingStore, store unless File.directory?(root)

        root
      end

      # The one database of a store folder: knowledge with work and retrieval attached. `origin` stamps its rows.
      def self.open_store(root, origin) = Store.new(root, origin)

      # The error to raise for one that came from the file `file`, with the file named.
      def self.relabeled(file, error)
        message = error.message
        return Plastic::Invalid.new("#{file}: #{message}") if error.is_a?(Plastic::Invalid)

        Error.new("#{file}: #{message.lines.first.chomp.delete_suffix(":")}")
      end

      # A call saves its command run at each step, and it is still one row.
      RUNS = "command_runs"

      attr_reader :path, :origin

      def_delegators :@tally, :wrote_rows?, :phrases
      def_delegator :@tally, :to_h, :written
      def_delegator :@tally, :phrase, :written_phrase
      def_delegator :@check, :key
      def_delegator :connection, :atomically

      # `key` names the schema of a database that is stamped; one without it is built from its schema alone. `layouts` maps each attached schema to its key.
      def initialize(path, schema, origin: nil, key: nil, layouts: { nil => key })
        name = File.basename(path)
        @path = path
        @origin = origin
        @check = Check.for(schema, key, name, layouts)
        @tally = Tally.new(name)
      end

      def file = File.basename(path)

      # Rows from one read. `:name` in the SQL takes the value of `name`.
      def rows(sql, **values) = connected { |connection| connection.read(sql, values) }

      def row(sql, **values) = rows(sql, **values).first

      # Every write of one call to this database, in one transaction. The
      # block adds statements to the Batch; the rows that RETURNING gives back
      # come back in the order the statements were added. A failed statement
      # rolls the whole batch back and raises Error.
      def transaction
        batch = Batch.new(origin:)
        yield batch
        batch.empty? ? [] : connected { |connection| connection.atomically { write(connection, batch) } }
      end

      # Runs the statements of the batch and always takes them back, so a
      # statement the database refuses raises Error and no row is written or counted.
      def dry_run
        batch = Batch.new(origin:)
        yield batch
        connected do |connection|
          connection.atomically do
            batch.execute(connection) { nil }
            raise Undone
          end
        end
      rescue Undone
        nil
      end

      # Runs a read snapshot and its derived writes in one immediate
      # transaction. The reader uses the same connection as the eventual
      # commit, so no writer can change the source rows between them.
      def immediate_transaction
        batch = Batch.new(origin:)
        connected do |connection|
          connection.atomically do
            yield batch, connection
            write(connection, batch) unless batch.empty?
          end
        end
      end

      # Brings the home database to the newest version by its SQL file. Only the install and the update call this.
      def migrate
        unfenced { SchemaMigrator.new(open_file, MIGRATIONS.of(:home).first.path).call }
        @check.pass
      end

      # Gives the freed pages of the file back to the disk. It runs outside a transaction.
      def vacuum = unfenced { open_file.execute("VACUUM") }

      # The stamped version of the file, or nil when it does not exist.
      def version = File.exist?(path) ? unfenced { open_file.get_first_value("PRAGMA user_version").to_i } : nil

      private

      def open_file = ConnectionPool.for(path)

      # Runs the block on the file itself, without the version check, and names the file in an error.
      def unfenced
        yield
      rescue Plastic::Invalid, SQLite3::Exception, SystemCallError => error
        raise Database.relabeled(file, error)
      end

      def write(connection, batch) = @tally.keeping { batch.execute(connection, &@tally.method(:count)) }

      def connected
        yield connection
      rescue Plastic::Invalid, SQLite3::Exception, SystemCallError => error
        raise Database.relabeled(file, error)
      end

      # The connection, checked on the first call: a new file gets its schema, a file behind its sequence is refused.
      def connection = open_file.tap { |connection| @check.call(connection) }
    end
  end
end

require_relative "database/journal_mode_refused"
require_relative "database/local"
require_relative "database/store"
