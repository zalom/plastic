# frozen_string_literal: true

module Plastic
  module Graph
    # Upgrades retrieval tables while retaining each canonical document row.
    module SchemaMigrations
      INTENT_STATES_COPY = <<~SQL
        INSERT INTO intents (id, intent_id, parent_id, ref, origin_id, slug, title, kind, status, disposition, reason, opened_at, closed_at, updated_at)
        SELECT id, intent_id, parent_id, ref, origin_id, slug, title, kind,
          CASE status WHEN 'active' THEN 'in_progress' ELSE status END,
          CASE status
            WHEN 'done' THEN 'delivered'
            WHEN 'abandoned' THEN CASE
              WHEN disposition IN ('superseded', 'cancelled') THEN disposition
              WHEN disposition LIKE '%superseded by%' THEN 'superseded'
              ELSE 'cancelled' END
            ELSE NULL END,
          CASE WHEN disposition IS NOT NULL AND disposition NOT IN ('delivered', 'superseded', 'cancelled') THEN disposition END,
          opened_at, closed_at, updated_at
        FROM intents_legacy;
        DELETE FROM sqlite_sequence WHERE name = 'intents';
        INSERT INTO sqlite_sequence (name, seq) SELECT 'intents', seq FROM sqlite_sequence WHERE name = 'intents_legacy';
      SQL

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

      def migrate_intent_states(connection)
        return unless outdated_intents?(connection)

        connection.transaction(:immediate) { run_swap(connection, :intents, INTENT_STATES_COPY) if outdated_intents?(connection) }
      end

      private

      def outdated_intents?(connection)
        sql = connection.get_first_value("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'intents'")
        !sql.nil? && (sql.include?("'active'") || !sql.include?('"reason"'))
      end

      def replace_legacy_table(connection, table, copy_sql) = connection.transaction(:immediate) { run_swap(connection, table, copy_sql) }

      def run_swap(connection, table, copy_sql)
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
