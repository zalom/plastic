# frozen_string_literal: true

module Plastic
  module Graph
    module SchemaMigrations
      def migrate_revision_membership(connection)
        sql = connection.get_first_value("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'document_revisions'")
        return unless sql&.include?('UNIQUE("sha256", "origin_id")')

        replace_legacy_table(connection, :document_revisions, <<~SQL)
          INSERT INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id)
          SELECT sha256, intent_id, path, body, created_at, origin_id FROM document_revisions_legacy;
        SQL
      end

      def migrate_passage_identity(connection)
        sql = connection.get_first_value("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'document_passages'")
        return unless sql
        return if sql.include?('"intent_id"')

        replace_legacy_table(connection, :document_passages, <<~SQL)
          INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id)
          SELECT p.sha256, r.intent_id, r.path, p.position, p.body, p.line_start, p.line_end, p.origin_id
          FROM document_passages_legacy p JOIN document_revisions r ON r.sha256 = p.sha256 AND r.origin_id = p.origin_id;
        SQL
      end

      private

      def replace_legacy_table(connection, table, copy_sql)
        connection.transaction(:immediate) do
          connection.execute_batch <<~SQL
            ALTER TABLE #{table} RENAME TO #{table}_legacy;
            #{ddl(table)}
            #{copy_sql}
            DROP TABLE #{table}_legacy;
          SQL
        end
      end
    end
  end
end
