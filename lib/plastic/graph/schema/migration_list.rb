# frozen_string_literal: true

module Plastic
  module Graph
    SchemaMigration = Data.define(:kind, :version, :path) do
      def sql = File.read(path)
    end

    # Docs: docs/contributing/MIGRATIONS.md.
    class MigrationList
      FOLDER = File.expand_path("../db/migrate", __dir__)
      VERSION_DIGITS = 14
      ALPHA_STAMP = 1

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

      def with(migration) = self.class.new([*@migrations, migration])

      def number(kind, value) = value.to_i.then { |stamp| (stamp == ALPHA_STAMP) ? baseline(kind).to_i : stamp }

      def known_number?(kind, number) = [0, *versions(kind).map(&:to_i)].include?(number)
    end

    MIGRATIONS = MigrationList.read(MigrationList::FOLDER)
  end
end
