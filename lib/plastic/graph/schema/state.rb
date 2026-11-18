# frozen_string_literal: true

require_relative "migration_list"

module Plastic
  module Graph
    # Docs: docs/contributing/MIGRATIONS.md.
    class SchemaState
      RECORDED = "SELECT group_concat(version, ' ') FROM main.schema_migrations"
      STAMP = "PRAGMA main.user_version"
      TABLES = "SELECT count(*) FROM main.sqlite_master WHERE name NOT LIKE 'sqlite_%'"

      Reading = Data.define(:name, :pending, :unknown, :adopted, :number) do
        def empty? = name == :empty

        def current? = name == :current

        def behind? = name == :behind

        def ahead? = name == :ahead

        def due?(refusal)
          raise refusal, "the database is newer than this code (it records #{unknown.join(", ")}); run plastic update" if ahead?

          !current?
        end
      end

      KINDS = { local: :home, knowledge: :store }.freeze

      def self.kind_of(key) = KINDS.fetch(key)

      def self.of_file(path, kind, migrations: MIGRATIONS)
        SQLite3::Database.open(path, readonly: true) { |database| new(database, kind, migrations:).call }
      end

      def initialize(connection, kind, migrations: MIGRATIONS)
        @connection = connection
        @kind = kind
        @migrations = migrations
      end

      def call
        recorded = recorded_versions
        recorded ? from_table(recorded) : from_stamp(@connection.get_first_value(STAMP).to_i)
      end

      private

      def known = @migrations.versions(@kind)

      def recorded_versions
        @connection.get_first_value(RECORDED).to_s.split
      rescue SQLite3::SQLException => error
        raise unless error.message.include?("no such table")
      end

      def from_table(recorded)
        unknown = recorded - known
        pending = known - recorded
        name = if unknown.any? then :ahead
        elsif pending.any? then :behind
        else :current
        end
        Reading.new(name:, pending:, unknown:, adopted: [], number: recorded.max.to_i)
      end

      def from_stamp(stamp)
        return alpha if stamp == MigrationList::ALPHA_STAMP
        return Reading.new(name: :ahead, pending: [], unknown: ["user_version #{stamp}"], adopted: [], number: stamp) unless stamp.zero?
        return Reading.new(name: :empty, pending: known, unknown: [], adopted: [], number: 0) if @connection.get_first_value(TABLES).zero?

        Reading.new(name: :behind, pending: known, unknown: [], adopted: [], number: 0)
      end

      def alpha
        baseline = @migrations.baseline(@kind)
        Reading.new(name: :behind, pending: known - [baseline], unknown: [], adopted: [baseline], number: baseline.to_i)
      end
    end
  end
end
