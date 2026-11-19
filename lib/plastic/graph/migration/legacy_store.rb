# frozen_string_literal: true

require_relative "../database"
require_relative "legacy_keep"
require_relative "legacy_table"

module Plastic
  module Graph
    # The files of one store with its legacy.db attached as `legacy`, for a down and a purge. legacy.db is attached only
    # when it is there, so a reading never makes the file. Docs: docs/contributing/MIGRATIONS.md.
    class LegacyStore
      attr_reader :root

      def initialize(home, slug)
        @root = File.join(home, "stores", slug)
      end

      def knowledge_file = File.join(@root, Schema.file(:knowledge))

      def connection = Database::ConnectionPool.for(knowledge_file, attach: Database::Store.attachments(knowledge_file).merge(legacy: legacy_file))

      # The legacy tables the migration `version` kept, none when legacy.db is not there.
      def tables(version) = File.file?(legacy_file) ? LegacyTable.of(connection, version) : []

      # The rows legacy.db holds, by version and then by table, none when legacy.db is not there.
      def kept
        return {} unless File.file?(legacy_file)

        LegacyTable.all(connection).group_by(&:version).transform_values { |tables| tables.to_h { |table| [table.table, table.count] } }
      end

      # Gives the pages that dropped legacy tables left back to the disk.
      def give_back = connection.give_back_free_pages(LegacyTable::SCHEMA)

      def release = Database::ConnectionPool.release(@root)

      private

      def legacy_file = File.join(@root, LegacyKeep::FILE)
    end
  end
end
