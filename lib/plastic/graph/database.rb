# frozen_string_literal: true

require_relative "missing_store"
require_relative "schema"
require_relative "schema/gate"
require_relative "sql"
require_relative "database/batch"
require_relative "database/connection_pool"

module Plastic
  module Graph
    # One SQLite file through the sqlite3 gem. The rows are the authority;
    # the files are printed from them.
    #
    # A write is one transaction. BEGIN IMMEDIATE takes the write lock first,
    # so two calls that both ask for the next intent id get two ids. Inside
    # an open transaction, such as a test's, the write is a savepoint. Each
    # database counts the rows that this call wrote, and the report prints
    # the counts on its `wrote:` line.
    class Database
      # A statement failed, or the file cannot be opened.
      class Error < StandardError; end

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

      # The three databases of one store folder. `origin` stamps their rows and their change log.
      def self.open_store(root, origin)
        Schema.store.to_h { |key| [key, new(File.join(root, Schema.file(key)), Schema.fetch(key), origin:, track: { sequence: :store, key: })] }
      end

      # The error to raise for one that came from the file `file`, with the file named.
      def self.relabeled(file, error)
        message = error.message
        return Plastic::Invalid.new("#{file}: #{message}") if error.is_a?(Plastic::Invalid)

        Error.new("#{file}: #{message.lines.first.chomp.delete_suffix(":")}")
      end

      # A call saves its command run at each step, and it is still one row.
      RUNS = "command_runs"

      attr_reader :path, :written

      # `track` names the migration sequence and the schema key of a database that is stamped; one without it is built from its schema alone.
      def initialize(path, schema, origin: nil, track: nil)
        @path = path
        @schema = schema
        @origin = origin
        @track = track
        @written = Hash.new(0)
      end

      def file = File.basename(path)

      # The schema key of a stamped database, or nil for one that is not.
      def key = @track&.fetch(:key)

      # Rows from one read. `:name` in the SQL takes the value of `name`.
      def rows(sql, **values) = connected { |connection| connection.read(sql, values) }

      def row(sql, **values) = rows(sql, **values).first

      # Every write of one call to this database, in one transaction. The
      # block adds statements to the Batch; the rows that RETURNING gives back
      # come back in the order the statements were added. A failed statement
      # rolls the whole batch back and raises Error.
      def transaction
        batch = Batch.new(origin: @origin)
        yield batch
        batch.empty? ? [] : commit(batch)
      end

      # Runs the statements of the batch and always takes them back, so a
      # statement the database refuses raises Error and no row is written or counted.
      def dry_run
        batch = Batch.new(origin: @origin)
        yield batch
        connected { |connection| connection.atomically { try(connection, batch) } }
      rescue Undone
        nil
      end

      # Runs a read snapshot and its derived writes in one immediate
      # transaction. The reader uses the same connection as the eventual
      # commit, so no writer can change the source rows between them.
      def immediate_transaction
        batch = Batch.new(origin: @origin)
        connected do |connection|
          connection.atomically do
            yield batch, connection
            write(connection, batch) unless batch.empty?
          end
        end
      end

      # Runs the block in one transaction on this file; a write inside it joins that transaction.
      def atomically(&) = connection.atomically(&)

      # What this call wrote here, as the report says it:
      # "1 intent and 1 work log line in work_graph.db". The command run row is left out,
      # and the phrase is nil when nothing else was written.
      def written_phrase = wrote_rows? ? "#{Schema.phrase(written.except(RUNS))} in #{file}" : nil

      # Whether this call wrote a row other than its command run.
      def wrote_rows? = written.keys.any? { |table| table != RUNS }

      # What the report says of this database: what this call wrote.
      def phrases = [written_phrase].compact

      # Brings the file to the newest version of its sequence. Only the install and the update call this.
      # `siblings` names the path of each other file of the store, by key, for a step that moves rows between files.
      def migrate(sequences, siblings: {})
        unfenced { SchemaSequences.migrate(open_file, sequences.fetch(@track.fetch(:sequence)), @track.fetch(:key), siblings) }
        @schema = nil
      end

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

      def commit(batch) = connected { |connection| connection.atomically { write(connection, batch) } }

      def write(connection, batch)
        counted = @written.dup
        batch.statements.filter_map { |entry| entry.execute(connection, &method(:count)) }
      rescue
        @written.replace(counted)
        raise
      end

      def try(connection, batch)
        batch.statements.each { |entry| entry.execute(connection) { nil } }
        raise Undone
      end

      def count(table, rows)
        before = @written[table]
        @written[table] = (table == RUNS) ? [before, rows].max : before + rows
      end

      def connected
        yield connection
      rescue Plastic::Invalid, SQLite3::Exception, SystemCallError => error
        raise Database.relabeled(file, error)
      end

      # The connection, checked on the first call: a new file gets its schema, a file behind its sequence is refused.
      def connection
        open_file.tap do |connection|
          settle(connection) if @schema
          @schema = nil
        end
      end

      def settle(connection)
        return Schema.prepare(connection, @schema) unless @track

        SchemaGate.new(connection, **@track, file:).call
      end
    end
  end
end

require_relative "database/local"
