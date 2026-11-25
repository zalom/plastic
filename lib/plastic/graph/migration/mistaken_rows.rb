# frozen_string_literal: true

require_relative "legacy_table"

module Plastic
  module Graph
    # Deletes from legacy.db the copy of what an agent created by mistake. legacy.db keeps only the owner's data, so the
    # copy of the table document_revisions that migration 20261119000000 kept goes, with no copy and no undo, and the
    # pages it held go back to the disk so the old text is not left in the file. The owner ruled this on 24 November
    # 2026. A store with no legacy.db, or with no such table, changes nothing. Its down removes the version alone.
    # Docs: docs/contributing/MIGRATIONS.md.
    class MistakenRows
      # The versions that delete a mistaken copy from an existing legacy.db, with the table each one deletes.
      TABLES = { "20261124150000" => "document_revisions_20261119000000" }.freeze
      VERSIONS = TABLES.keys.freeze
      SCHEMA = LegacyTable::SCHEMA
      ATTACHED = "SELECT count(*) FROM pragma_database_list WHERE name = ?"

      # The rows it deleted, by the table they were in.
      Result = Data.define(:deleted) do
        def line(slug)
          return if deleted.empty?

          deleted.map { |table, rows| "migrate: #{slug} deleted #{rows} #{(rows == 1) ? "row" : "rows"} of #{table} from legacy.db, an agent's mistake with no copy and no undo" }.join("\n")
        end
      end

      # `keep` is the keep of the data step; this step keeps nothing, since it deletes.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call
        return Result.new(deleted: {}) unless @connection.get_first_value(ATTACHED, [SCHEMA]).positive?

        deleted = TABLES.values.to_h { |name| [name.sub(/_\d{14}\z/, ""), delete(name)] }.reject { |_table, rows| rows.nil? }
        Result.new(deleted:)
      end

      private

      # The number of rows the table held, or nil when legacy.db has no such table.
      def delete(name)
        return unless @connection.get_first_value("SELECT count(*) FROM #{SCHEMA}.sqlite_master WHERE type = 'table' AND name = ?", [name]).positive?

        @connection.get_first_value(%(SELECT count(*) FROM #{SCHEMA}."#{name}")).tap { @connection.execute(%(DROP TABLE #{SCHEMA}."#{name}")) }
      end
    end
  end
end
