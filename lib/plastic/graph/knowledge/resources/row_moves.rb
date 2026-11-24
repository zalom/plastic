# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Moves the rows of the files a repair moves, in one transaction of the store: the documents, their heads and the legacy rows
        # by path inside the intent, the kept files and the printed files by path inside the store. The
        # moves load into a temporary table, so each table takes one statement however many files move. A row
        # already at a target stops the transaction.
        class RowMoves
          BY_INTENT = %w[documents document_heads legacy_intents_data].freeze
          BY_STORE = { "sqlar" => "name", "printed" => "path" }.freeze
          CREATE = "CREATE TEMP TABLE row_moves (intent_id, inside_from, inside_to, from_path, to_path)"
          LOAD = <<~SQL
            INSERT INTO row_moves
            SELECT json_extract(value, '$[0]'), json_extract(value, '$[1]'), json_extract(value, '$[2]'), json_extract(value, '$[3]'), json_extract(value, '$[4]')
            FROM json_each(:moves)
          SQL
          DROP = "DROP TABLE row_moves"

          def self.moving
            by_intent = BY_INTENT.map { |table| "UPDATE #{table} SET path = m.inside_to FROM row_moves m WHERE #{table}.intent_id = m.intent_id AND #{table}.path = m.inside_from" }
            by_store = BY_STORE.map { |table, column| "UPDATE #{table} SET #{column} = m.to_path FROM row_moves m WHERE #{table}.#{column} = m.from_path" }
            by_intent + by_store
          end

          def self.dropping
            by_intent = BY_INTENT.map { |table| "DELETE FROM #{table} WHERE (intent_id, path) IN (SELECT intent_id, inside_from FROM row_moves)" }
            by_store = BY_STORE.map { |table, column| "DELETE FROM #{table} WHERE #{column} IN (SELECT from_path FROM row_moves)" }
            by_intent + by_store
          end

          def self.script(batch, moves, statements)
            batch.add(CREATE)
            batch.add(LOAD, moves: moves.map(&:row).to_json)
            statements.each { |sql| batch.add(sql) }
            batch.add(DROP)
          end

          def initialize(database)
            @database = database
          end

          def call(moves) = transact(moves, RowMoves.moving)

          def drop(moves) = transact(moves, RowMoves.dropping)

          private

          def transact(moves, statements)
            return if moves.empty?

            @database.transaction { |batch| RowMoves.script(batch, moves, statements) }
          end
        end
      end
    end
  end
end
