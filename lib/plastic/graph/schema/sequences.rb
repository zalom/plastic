# frozen_string_literal: true

require_relative "sequences/home_1"
require_relative "sequences/home_2"
require_relative "sequences/home_3"
require_relative "sequences/home_4"

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

      SEQUENCES = {
        home: [Migration.new(1, SchemaHome1.method(:apply), SchemaHome1::TABLES),
          Migration.new(2, SchemaHome2.method(:apply), SchemaHome2::TABLES),
          Migration.new(3, SchemaHome3.method(:apply), SchemaHome3::TABLES),
          Migration.new(4, SchemaHome4.method(:apply), SchemaHome4::TABLES)].freeze
      }.freeze

      VERSION = "PRAGMA user_version"

      module_function

      def newest(sequence) = SEQUENCES.fetch(sequence).last.number

      def pending(sequence, version) = SEQUENCES.fetch(sequence).select { |migration| migration.number > version }

      # Runs the migrations above the stamped version in order. Each one commits
      # with its stamp inside one immediate transaction, after the stamp is read
      # again under the lock, so a second runner waits and finds the work done.
      def migrate(connection, migrations, key)
        migrations.each do |migration|
          next if stamped(connection) >= migration.number

          connection.transaction(:immediate) { apply_once(connection, migration, key) }
        end
      end

      def apply_once(connection, migration, key)
        return if stamped(connection) >= migration.number

        migration.apply.call(connection, key)
        connection.execute("#{VERSION} = #{migration.number}")
      end

      def stamped(connection) = connection.get_first_value(VERSION).to_i
    end
  end
end
