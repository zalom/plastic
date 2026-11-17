# frozen_string_literal: true

require_relative "sequences/home_1"
require_relative "sequences/home_2"
require_relative "sequences/home_3"
require_relative "sequences/home_4"
require_relative "sequences/store_1"
require_relative "sequences/store_2"
require_relative "sequences/store_3"
require_relative "sequences/store_4"
require_relative "sequences/store_5"
require_relative "sequences/store_6"

module Plastic
  module Graph
    # The two migration sequences, home and store, each numbered 1 to N. The
    # number of the last migration that ran on a database is its
    # PRAGMA user_version. A migration is never edited once it has landed: it
    # holds its own statements, written out, and a later change to the schema
    # is a later migration. Each migration and its stamp commit together under
    # the write lock, so a run that stopped halfway leaves the file as it was.
    module SchemaSequences
      # One step of a sequence: `apply` takes the connection and the database key, and
      # `tables` names the tables of each database file once the step has run.
      Migration = Data.define(:number, :apply, :tables)

      # The tables of each store database before any migration ran, which is
      # what a backup of an unstamped store holds.
      BASELINE_TABLES = {
        "work_graph" => %w[intents clusters nodes edges savepoints completions printed changes roadmaps batches roadmap_items
          roadmap_edges roadmap_log archives archive_entries],
        "knowledge_graph" => %w[documents document_revisions document_heads document_passages document_fts retrieval_schema
          retrieval_backfills retrieval_contexts retrieval_discoveries rulings links printed changes],
        "references" => %w[sqlar printed changes]
      }.freeze

      # The declared schema as it is today, for a new, empty file: it is built whole and stamped with the newest number.
      CURRENT_LAYOUT = ->(connection, key) { connection.execute_batch(Schema.fetch(key)) }

      SEQUENCES = {
        home: [Migration.new(1, SchemaHome1.method(:apply), SchemaHome1::TABLES),
          Migration.new(2, SchemaHome2.method(:apply), SchemaHome2::TABLES),
          Migration.new(3, SchemaHome3.method(:apply), SchemaHome3::TABLES),
          Migration.new(4, SchemaHome4.method(:apply), SchemaHome4::TABLES)].freeze,
        store: [Migration.new(1, SchemaStore1.method(:apply), SchemaStore1::TABLES),
          Migration.new(2, SchemaStore2.method(:apply), SchemaStore2::TABLES),
          Migration.new(3, SchemaStore3.method(:apply), SchemaStore3::TABLES),
          Migration.new(4, SchemaStore4.method(:apply), SchemaStore4::TABLES),
          Migration.new(5, SchemaStore5.method(:apply), SchemaStore5::TABLES),
          Migration.new(6, SchemaStore6.method(:apply), SchemaStore6::TABLES)].freeze
      }.freeze

      VERSION = "PRAGMA user_version"

      module_function

      def newest(sequence) = SEQUENCES.fetch(sequence).last.number

      def pending(sequence, version) = SEQUENCES.fetch(sequence).select { |migration| migration.number > version }

      # The tables the database file `name` holds at `version` of the migrations.
      def tables(migrations, version, name)
        return BASELINE_TABLES.fetch(name) if version.zero?

        migrations.find { |migration| migration.number == version }.tables.fetch(name)
      end

      # Runs the migrations above the stamped version in order. Each one commits
      # with its stamp inside one immediate transaction, after the stamp is read
      # again under the lock, so a second runner waits and finds the work done.
      # `siblings` names the other files of the store, by key, for a step that moves rows between files.
      def migrate(connection, migrations, key, siblings = {})
        migrations.each do |migration|
          next if stamped(connection) >= migration.number

          connection.transaction(:immediate) { apply_once(connection, migration, key, siblings) }
        end
      end

      def apply_once(connection, migration, key, siblings)
        return if stamped(connection) >= migration.number

        (migration.apply.arity == 2) ? migration.apply.call(connection, key) : migration.apply.call(connection, key, siblings)
        connection.execute("#{VERSION} = #{migration.number}")
      end

      def stamped(connection) = connection.get_first_value(VERSION).to_i
    end
  end
end
