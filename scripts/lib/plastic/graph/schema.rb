# frozen_string_literal: true

require_relative "table"
require_relative "knowledge/intent"
require_relative "knowledge/roadmap"
require_relative "schema/metadata"
require_relative "schema/migrations"
require_relative "schema/catalog"

module Plastic
  module Graph
    # Builds database DDL and exposes the tables that Plastic's graph uses.
    module Schema
      extend SchemaMigrations

      def self.file(key) = databases.fetch(key).first

      def self.fetch(key) = [*databases.fetch(key).last.map { |name| ddl(name) }, migrations[key]].compact.join("\n")

      def self.prepare(connection, schema)
        connection.execute_batch(schema)
        migrate_revision_membership(connection)
        migrate_passage_identity(connection)
      end

      def self.table_named(name) = tables.fetch(name.to_sym)

      def self.ddl(name) = SchemaCatalog::VIRTUAL.fetch(name) { table_named(name).ddl }

      def self.tally(table, count)
        name = table.to_s
        one, many = nouns.fetch(name) { [name, name] }
        "#{count} #{(count == 1) ? one : many}"
      end

      def self.phrase(counts)
        *rest, last = counts.map { |table, count| tally(table, count) }
        return last if rest.empty?

        (rest.size == 1) ? "#{rest.first} and #{last}" : "#{rest.join(", ")}, and #{last}"
      end

      def self.databases = SchemaCatalog::DATABASES
      def self.store = SchemaCatalog::STORE
      def self.tables = SchemaCatalog::TABLES
      def self.legacy_tables = SchemaCatalog::MARKS.fetch(:legacy)
      def self.later_tables = SchemaCatalog::MARKS.fetch(:since)

      def self.migrations = SchemaMetadata::MIGRATIONS
      def self.nouns = SchemaMetadata::NOUNS
    end
  end
end
