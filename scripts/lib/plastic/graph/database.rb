# frozen_string_literal: true

require_relative "schema"
require_relative "sql"
require_relative "database/batch"
require_relative "database/program"

module Plastic
  module Graph
    # One SQLite file. The rows are the authority; the files are printed
    # from them. `engine` runs each script, by default the sqlite3 program.
    #
    # A write is one transaction in one sqlite3 process. BEGIN IMMEDIATE takes
    # the write lock first, so two calls that both ask for the next intent id
    # get two ids. Each database counts the rows that this call wrote, and the
    # report prints the counts on its `wrote:` line.
    class Database
      # The sqlite3 program is missing, or a statement failed.
      class Error < StandardError; end

      # One file and the engine that runs each script against it.
      Connection = Data.define(:path, :engine)

      # Runs a script against its file.
      class Connection
        def call(script) = engine.call(path, script)
      end

      # The database of the home, for what belongs to one machine.
      def self.open_home(home, engine: Program.new)
        engine.check
        { home: new(File.join(home, Schema.file(:home)), Schema.fetch(:home), engine:) }
      end

      # The three databases of one store folder. `origin` stamps their rows and their change log.
      def self.open_store(root, origin, engine: Program.new)
        engine.check
        Schema::STORE.to_h { |key| [key, new(File.join(root, Schema.file(key)), Schema.fetch(key), origin:, engine:)] }
      end

      attr_reader :written

      def initialize(path, schema, origin: nil, engine: Program.new)
        @connection = Connection.new(path, engine)
        @schema = schema
        @origin = origin
        @written = Hash.new(0)
      end

      def path = @connection.path

      def file = File.basename(path)

      # Rows from one read. `:name` in the SQL takes the value of `name`.
      def rows(sql, **values) = execute(SQL.bind(sql, values)).first || []

      def row(sql, **values) = rows(sql, **values).first

      # Every write of one call to this database, in one transaction. The
      # block adds statements to the Batch; the rows that RETURNING gives back
      # come back in the order the statements were added.
      def transaction
        batch = Batch.new(origin: @origin)
        yield batch
        batch.empty? ? [] : commit(batch)
      end

      # What this call wrote here, as the report says it:
      # "1 intent and 1 savepoint line in work_graph.db". Nil when nothing.
      def written_phrase = written.empty? ? nil : "#{Schema.phrase(written)} in #{file}"

      private

      def commit(batch)
        tallies, returned = execute(batch.script).partition { |set| set.first.key?("written_table") }
        tallies.flatten.each { |tally| count(*tally.values_at("written_table", "written_rows")) }
        returned
      end

      def count(table, rows) = @written[table] += rows

      # The schema goes first in the first script of the call, so a new
      # folder needs no separate setup step.
      def execute(script)
        sets = @connection.call(with_schema(script))
        @schema = nil
        sets
      end

      def with_schema(script) = @schema ? "#{@schema}\n#{script}" : script
    end
  end
end
