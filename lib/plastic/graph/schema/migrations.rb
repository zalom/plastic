# frozen_string_literal: true

module Plastic
  module Graph
    # Upgrades retrieval tables while retaining each canonical document row.
    module SchemaMigrations
      SEARCH_TABLES = %i[document_revisions document_passages].freeze

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

      # Whether the intents table still has the old word for work under way or no reason column.
      module IntentsTable
        SQL = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'intents'"
        OUTDATED = /'active'|\A(?!.*"reason")/m

        module_function

        def outdated?(connection) = connection.get_first_value(SQL)&.match?(OUTDATED)
      end

      # Whether the locks table still names its time column the way older releases do.
      module LocksTable
        SQL = "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'locks'"
        HELD = "local.db is held by another process; run the command again when it is free"

        module_function

        def older?(connection) = connection.get_first_value(SQL)&.include?("taken_at") || false
      end

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

      # The triggers of a table, as the statements that make them and drop them.
      def trigger_creates(table) = triggers_on(table).map(&:create)

      def trigger_drops(table) = triggers_on(table).map(&:drop)

      # Renames the column of locks that older releases call taken_at. The check runs again inside the immediate
      # transaction, so a second process finds the column renamed and does nothing.
      def migrate_lock_column(connection)
        return unless LocksTable.older?(connection)

        connection.transaction(:immediate) do
          connection.execute("ALTER TABLE locks RENAME COLUMN taken_at TO locked_at") if LocksTable.older?(connection)
        end
      rescue SQLite3::BusyException
        raise Database::Error, LocksTable::HELD
      end

      def migrate_intent_states(connection) = (connection.transaction(:immediate) { swap_outdated(connection) } if IntentsTable.outdated?(connection))

      private

      def triggers_on(table) = triggers.values.select { |trigger| trigger.on == table }

      def guarded_by(table) = SEARCH_TABLES.include?(table) ? :document_heads : nil

      def swap_outdated(connection) = (run_swap(connection, :intents, INTENT_STATES_COPY) if IntentsTable.outdated?(connection))

      def replace_legacy_table(connection, table, copy_sql) = connection.transaction(:immediate) { run_swap(connection, table, copy_sql) }

      def run_swap(connection, table, copy_sql)
        guarded = guarded_by(table)
        connection.execute_batch <<~SQL
          #{trigger_drops(guarded).join("\n")}
          ALTER TABLE #{table} RENAME TO #{table}_legacy;
          #{ddl(table)}
          #{copy_sql}
          DROP TABLE #{table}_legacy;
          #{trigger_creates(guarded).join("\n")}
        SQL
      end
    end
  end
end
