# frozen_string_literal: true

module Plastic
  module Graph
    # One migration: the kind of database it changes, its version, which is a 14-digit UTC timestamp, and its SQL file.
    SchemaMigration = Data.define(:kind, :version, :path) do
      def sql = File.read(path)
    end

    # The migrations of every kind of database, in ascending order of version. The code reads the folders of
    # db/migrate once, at load time, into MIGRATIONS. Docs: docs/contributing/MIGRATIONS.md.
    class MigrationList
      FOLDER = File.expand_path("../db/migrate", __dir__)
      VERSION_DIGITS = 14

      def self.read(folder)
        new(Dir.glob(File.join(folder, "*", "*.sql")).map { |path| migration_at(path) })
      end

      def self.migration_at(path)
        SchemaMigration.new(kind: File.basename(File.dirname(path)).to_sym, version: File.basename(path)[0, VERSION_DIGITS], path:)
      end
      private_class_method :migration_at

      def initialize(migrations)
        @migrations = migrations.sort_by { |migration| [migration.kind, migration.version] }.freeze
        freeze
      end

      def of(kind) = @migrations.select { |migration| migration.kind == kind }

      def versions(kind) = of(kind).map(&:version)

      def baseline(kind) = versions(kind).first

      def newest(kind) = versions(kind).last

      def newest_of_any = @migrations.map(&:version).max

      # The same list with one more migration, as a test adds a later one.
      def with(migration) = self.class.new([*@migrations, migration])

      # A version as a number. 0 is a beta.2 file, and 1, the stamp an alpha build wrote, reads as the baseline.
      def number(kind, value) = (value.to_i == 1) ? baseline(kind).to_i : value.to_i

      def known_number?(kind, number) = number.zero? || versions(kind).include?(number.to_s)
    end

    MIGRATIONS = MigrationList.read(MigrationList::FOLDER)
  end
end
