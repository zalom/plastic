# frozen_string_literal: true

require "sqlite3"
require_relative "migration_list"

module Plastic
  module Graph
    # What one database file records against the migrations of this code. A file with a schema_migrations table is
    # current when it records every version of its kind, behind when it lacks one, and ahead when it records one this
    # code does not know. A file with no such table is empty, a beta.2 file (user_version 0 with tables), an alpha file
    # (user_version 1, which has the baseline), or ahead at any other stamp. Docs: docs/contributing/MIGRATIONS.md.
    class SchemaState
      RECORDED = "SELECT group_concat(version, ' ') FROM main.schema_migrations"
      STAMP = "PRAGMA main.user_version"
      TABLES = "SELECT count(*) FROM main.sqlite_master WHERE name NOT LIKE 'sqlite_%'"
      ALPHA_STAMP = 1

      # `adopted` names the versions a file has without a row, which the migrator records and runs no SQL for.
      Reading = Data.define(:name, :pending, :unknown, :adopted, :stamp, :number) do
        def empty? = name == :empty

        def current? = name == :current

        def behind? = name == :behind

        def ahead? = name == :ahead
      end

      # The kind of migrations a stamped schema key takes: the home file takes the home migrations, a store the store ones.
      def self.kind_of(key) = (key == :local) ? :home : :store

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
        Reading.new(name:, pending:, unknown:, adopted: [], stamp: nil, number: recorded.max.to_i)
      end

      def from_stamp(stamp)
        return alpha(stamp) if stamp == ALPHA_STAMP
        return Reading.new(name: :ahead, pending: [], unknown: ["user_version #{stamp}"], adopted: [], stamp:, number: stamp) unless stamp.zero?
        return Reading.new(name: :empty, pending: known, unknown: [], adopted: [], stamp:, number: 0) if @connection.get_first_value(TABLES).zero?

        Reading.new(name: :behind, pending: known, unknown: [], adopted: [], stamp:, number: 0)
      end

      def alpha(stamp)
        baseline = @migrations.baseline(@kind)
        Reading.new(name: :behind, pending: known - [baseline], unknown: [], adopted: [baseline], stamp:, number: baseline.to_i)
      end
    end
  end
end
