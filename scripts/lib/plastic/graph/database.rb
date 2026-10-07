# frozen_string_literal: true

require_relative "schema"
require_relative "sql"
require_relative "database/batch"
require_relative "database/connection_pool"
require_relative "database/former_name"

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

      # The local database, for what belongs to one machine. A home.db left
      # from before becomes local.db on the first use.
      def self.open_local(home)
        former = FormerName.new(File.join(home, "home.db"))
        { local: new(File.join(home, Schema.file(:local)), Schema.fetch(:local), former:) }
      end

      # The three databases of one store folder. `origin` stamps their rows and their change log.
      def self.open_store(root, origin)
        Schema.store.to_h { |key| [key, new(File.join(root, Schema.file(key)), Schema.fetch(key), origin:)] }
      end

      attr_reader :path, :written

      def initialize(path, schema, origin: nil, former: nil)
        @path = path
        @schema = schema
        @origin = origin
        @former = former
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

      # The rename this call made, then what it wrote.
      def phrases = [@renamed, written_phrase].compact

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
        rename_former
        ConnectionPool.for(path).tap do |connection|
          Schema.prepare(connection, @schema) if @schema
          @schema = nil
        end
      end

      def rename_former
        @renamed = @former.move_to(path) if @former
        @former = nil
      end
    end
  end
end
