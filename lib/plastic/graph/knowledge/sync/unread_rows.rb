# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The rows of each intent file the sync rules no longer read, such as a file read under older rules or a
        # report that is neither recorded nor mandatory. A sync up removes them from documents, document_heads,
        # printed and the search index, of every origin, and leaves the file on disk.
        class UnreadRows
          PAIRS = "SELECT json_extract(value, '$[0]') AS intent_id, json_extract(value, '$[1]') AS path FROM json_each(:rows)"
          STEPS = [
            ["documents", "DELETE FROM main.documents WHERE (intent_id, path) IN (#{PAIRS})"],
            ["document_heads", "DELETE FROM main.document_heads WHERE (intent_id, path) IN (#{PAIRS})"],
            ["printed", "DELETE FROM main.printed WHERE path IN (SELECT value FROM json_each(:printed))"],
            ["document_passages", "DELETE FROM retrieval.document_passages WHERE (intent_id, path) IN (#{PAIRS})"],
            ["document_fts", "DELETE FROM retrieval.document_fts WHERE (intent_id, path) IN (#{PAIRS})"]
          ].freeze
          DOCUMENTS = "SELECT DISTINCT intent_id, path FROM main.documents WHERE intent_id <> '' ORDER BY intent_id, path"
          WHY = "the sync no longer reads it"

          Row = Data.define(:intent_id, :path, :printed)

          attr_reader :rows

          def self.none = new([])

          # The rows of `database` whose path `selection` does not read; `dirs` maps an intent id to its folder.
          def self.find(selection, database, dirs)
            unread = database.rows(DOCUMENTS).reject { |row| selection.read?(row.fetch("path"), intent_id: row.fetch("intent_id")) }
            new(unread.map { |row| Row.new(row.fetch("intent_id"), row.fetch("path"), "#{dirs.fetch(row.fetch("intent_id"), "store/#{row.fetch("intent_id")}--")}/#{row.fetch("path")}") })
          end

          def initialize(rows)
            @rows = rows
          end

          def size = rows.size

          def remove(database)
            return [] if rows.empty?

            database.transaction { |batch| batch.add_steps(STEPS, **values) }
            rows.map { |row| "removed the rows of #{row.printed}: #{WHY}" }
          end

          private

          def values = { rows: JSON.generate(rows.map { |row| [row.intent_id, row.path] }), printed: JSON.generate(rows.map(&:printed)) }
        end
      end
    end
  end
end
