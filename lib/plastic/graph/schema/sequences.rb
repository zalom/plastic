# frozen_string_literal: true

module Plastic
  module Graph
    # The two migration sequences, home and store, each numbered 1 to N. The
    # number of the last migration that ran on a database is its
    # PRAGMA user_version. A migration is idempotent, so a run that stopped
    # halfway runs again clean, and it is never edited once it has landed.
    module SchemaSequences
      # One step of a sequence: `apply` takes the connection and the database key.
      Migration = Data.define(:number, :apply)

      CURRENT_LAYOUT = ->(connection, key) { Schema.prepare(connection, Schema.fetch(key)) }

      SEQUENCES = {
        home: [Migration.new(1, CURRENT_LAYOUT)].freeze,
        store: [Migration.new(1, CURRENT_LAYOUT)].freeze
      }.freeze

      module_function

      def newest(sequence) = SEQUENCES.fetch(sequence).last.number

      def pending(sequence, version) = SEQUENCES.fetch(sequence).select { |migration| migration.number > version }

      # Runs the migrations above the stamped version in order, and stamps
      # each number once its migration has succeeded.
      def migrate(connection, migrations, key)
        version = connection.get_first_value("PRAGMA user_version").to_i
        migrations.select { |migration| migration.number > version }.each do |migration|
          migration.apply.call(connection, key)
          connection.execute("PRAGMA user_version = #{migration.number}")
        end
      end
    end
  end
end
