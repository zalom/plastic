# frozen_string_literal: true

require_relative "schema"
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

      # The local database, for what belongs to one machine.
      def self.open_local(home) = { local: Local.new(home) }

      # The three databases of one store folder. `origin` stamps their rows and their change log.
      def self.open_store(root, origin)
        Schema.store.to_h { |key| [key, new(File.join(root, Schema.file(key)), Schema.fetch(key), origin:)] }
      end

      attr_reader :path, :written

      def initialize(path, schema, origin: nil)
        @path = path
        @schema = schema
        @origin = origin
        @written = Hash.new(0)
      end

      def file = File.basename(path)

      # Rows from one read. `:name` in the SQL takes the value of `name`.
      def rows(sql, **values) = connected { |connection| connection.sets(SQL.bind(sql, values)) }.first || []

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

      # Runs a read snapshot and its derived writes in one immediate
      # transaction. The reader uses the same connection as the eventual
      # commit, so no writer can change the source rows between them.
      def immediate_transaction
        batch = Batch.new(origin: @origin)
        connected do |connection|
          connection.atomically do
            yield batch, connection
            tally(connection.sets(batch.statements.join)) unless batch.empty?
          end
        end
      end

      # What this call wrote here, as the report says it:
      # "1 intent and 1 savepoint line in work_graph.db". Nil when nothing.
      def written_phrase = written.empty? ? nil : "#{Schema.phrase(written)} in #{file}"

      # What the report says of this database: what this call wrote.
      def phrases = [written_phrase].compact

      private

      def commit(batch)
        script = batch.statements.join
        tally(connected { |connection| connection.atomically { connection.sets(script) } })
      end

      def tally(sets)
        tallies, returned = sets.partition { |set| set.first.key?("written_table") }
        tallies.flatten.each { |tally| count(*tally.values_at("written_table", "written_rows")) }
        returned
      end

      def count(table, rows) = @written[table] += rows

      def connected
        yield connection
      rescue SQLite3::Exception, SystemCallError => error
        raise Error, "#{file}: #{error.message.lines.first.chomp.delete_suffix(":")}"
      end

      # The connection, with the schema made on the first call, so a new
      # folder needs no separate setup step.
      def connection
        ConnectionPool.for(path).tap do |connection|
          Schema.prepare(connection, @schema) if @schema
          @schema = nil
        end
      end
    end
  end
end

require_relative "database/local"
