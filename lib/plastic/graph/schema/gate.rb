# frozen_string_literal: true

require_relative "../behind"
require_relative "migration_list"
require_relative "migrator"
require_relative "state"

module Plastic
  module Graph
    # The check a database passes on its first use in a process. The schema_migrations table of the main file says
    # whether the whole database is current. A new, empty database gets the declared schema of each of its files and a
    # row for every version of its kind, and runs no migration. A database that records every version passes. A database behind is refused after one wait for the write lock, because
    # another session may be migrating it; a database ahead of this code is refused too. Nothing here migrates an old
    # file: the install and the update do, through SchemaRunner.
    class SchemaGate
      MAIN = "main"

      # True when the main file of a store lacks a version of this code, or is empty while another file holds tables.
      def self.behind?(path, files)
        existing = [path, *files].select { |file| File.file?(file) }
        return false if existing.empty?

        reading = main_reading(path)
        return reading.behind? unless reading.empty?

        existing.any? { |file| holding_tables?(file) }
      rescue SQLite3::Exception
        false
      end

      def self.main_reading(path) = File.file?(path) ? SchemaState.of_file(path, :store) : SchemaState::Reading.new(name: :empty, pending: [], unknown: [], adopted: [], number: 0)

      def self.holding_tables?(path) = SQLite3::Database.open(path, readonly: true) { |database| database.get_first_value("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'").positive? }

      # `layouts` maps each schema of the connection, nil for a database of one file, to the schema key that builds it; the first is the main file.
      def initialize(connection, layouts:, file:, migrations: MIGRATIONS)
        @connection = connection
        @layouts = layouts
        @file = file
        @migrations = migrations
      end

      def call
        reading = state
        return build_missing_files if reading.current?

        raise Ahead, refusal("is newer than this code (it records #{reading.unknown.join(", ")})") if reading.ahead?

        settle
      rescue SQLite3::BusyException
        raise Behind, refusal("is busy and behind this code")
      end

      private

      def state = SchemaState.new(@connection, kind, migrations: @migrations).call

      def kind = SchemaState.kind_of(@layouts.values.first)

      def prefix(schema) = schema && "#{schema}."

      def empty? = @layouts.keys.all? { |schema| empty_schema?(schema) }

      def empty_schema?(schema) = @connection.get_first_value("SELECT COUNT(*) FROM #{prefix(schema)}sqlite_master WHERE name NOT LIKE 'sqlite_%'").zero?

      # An attached file that was lost, such as the derived retrieval file, is built again empty; the rows of the main file stay.
      def build_missing_files
        return if lost_schemas.empty?

        under_write_lock { lost_schemas.each { |schema| @connection.execute_batch(Schema.fetch(@layouts.fetch(schema), schema:)) } }
      end

      def lost_schemas = @layouts.keys.compact.select { |schema| empty_schema?(schema) }

      def settle
        return if empty? && build_layout

        verify_current
      end

      # Builds the declared schema of every file and records every version of its kind in one transaction under the write lock. A second
      # session that waited for the lock finds the tables there and builds nothing.
      def build_layout
        under_write_lock do
          next false unless empty?

          @layouts.each { |schema, key| @connection.execute_batch(Schema.fetch(key, schema:)) }
          SchemaMigrator.record(@connection, @migrations.versions(kind))
          true
        end
      end

      def verify_current
        current = under_write_lock { state }
        raise Behind, refusal("is behind this code (it lacks #{(current.adopted + current.pending).join(", ")})") unless current.current?
      end

      # A call already inside a transaction holds the write lock or will; a call outside one takes it here.
      def under_write_lock(&)
        return yield if @connection.transaction_active?

        @connection.transaction(:immediate, &)
      end

      def refusal(reason) = "#{@file} #{reason}; run plastic update"
    end
  end
end
