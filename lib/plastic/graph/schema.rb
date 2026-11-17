# frozen_string_literal: true

require_relative "table"
require_relative "knowledge/intent"
require_relative "knowledge/roadmap"
require_relative "schema/metadata"
require_relative "schema/catalog"

module Plastic
  module Graph
    # Builds database DDL and exposes the tables that Plastic's graph uses.
    module Schema
      class UnknownTable < KeyError; end

      def self.file(key) = databases.fetch(key).first

      # The file that holds the table `name`.
      def self.file_of(name)
        absent = -> { raise UnknownTable, "no database file holds the table #{name}" }
        databases.values_at(*store, *derived).find(absent) { |_file, names| names.include?(name.to_sym) }.first
      end

      def self.fetch(key, schema: nil)
        names = databases.fetch(key).last
        names.map { |name| ddl(name, schema) }.join("\n")
      end

      def self.prepare(connection, schema) = connection.execute_batch(schema)

      def self.table_named(name) = tables.fetch(name.to_sym)

      def self.ddl(name, schema = nil) = SchemaCatalog::VIRTUAL.fetch(name) { table_named(name) }.ddl(schema)

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
      def self.derived = SchemaCatalog::DERIVED
      def self.tables = SchemaCatalog::TABLES
      def self.later_tables = SchemaCatalog::MARKS.fetch(:since)

      def self.nouns = SchemaMetadata::NOUNS
    end
  end
end
