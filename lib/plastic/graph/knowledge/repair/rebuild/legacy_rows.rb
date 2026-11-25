# frozen_string_literal: true

require "json"
require "sqlite3"

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # Keeps in legacy.db the rows that held the files a repair removes, before the store drops them. A row already
          # kept is written again with the same values, so a second run changes nothing.
          class LegacyRows
            FILE = "legacy.db"
            TABLE = "legacy_intents_data"
            CREATE = "CREATE TABLE IF NOT EXISTS #{TABLE} (intent_id TEXT, path TEXT, body TEXT, updated_at TEXT, origin_id TEXT, PRIMARY KEY (intent_id, path, origin_id))".freeze
            SELECT = <<~SQL
              SELECT intent_id, path, body, updated_at, origin_id FROM #{TABLE}
              WHERE (intent_id, path) IN (SELECT json_extract(value, '$[0]'), json_extract(value, '$[1]') FROM json_each(:keys))
            SQL

            def initialize(root, store)
              @root = root
              @store = store
            end

            # Copies the rows of the removals, each a Removal, and answers how many it kept.
            def keep(removals)
              rows = @store.rows(SELECT, keys: removals.map { |removal| [removal.intent_id, removal.inside] }.to_json)
              return 0 if rows.empty?

              write(rows)
              rows.size
            end

            private

            def write(rows)
              database = SQLite3::Database.new(File.join(@root, FILE))
              database.transaction do
                database.execute(CREATE)
                rows.each { |row| database.execute("INSERT OR REPLACE INTO #{TABLE} VALUES (?, ?, ?, ?, ?)", row.values_at("intent_id", "path", "body", "updated_at", "origin_id")) }
              end
            ensure
              database&.close
            end
          end
        end
      end
    end
  end
end
