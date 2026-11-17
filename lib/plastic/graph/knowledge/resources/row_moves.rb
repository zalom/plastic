# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Moves the rows of the files a sort moves, in one transaction of the store: the documents, their heads and
        # revisions by path inside the intent, the kept files and the printed files by path inside the store.
        class RowMoves
          BY_INTENT = %w[documents document_heads document_revisions].freeze
          BY_STORE = { "sqlar" => "name", "printed" => "path" }.freeze

          def self.statements(move)
            intent = BY_INTENT.map { |table| ["UPDATE OR REPLACE #{table} SET path = :to WHERE intent_id = :id AND path = :from", { id: move.intent_id, from: move.inside_from, to: move.inside_to }] }
            store = BY_STORE.map { |table, column| ["UPDATE OR REPLACE #{table} SET #{column} = :to WHERE #{column} = :from", { from: move.from, to: move.to }] }
            intent + store
          end

          def self.write(batch, statements) = statements.each { |sql, values| batch.add(sql, **values) }

          def initialize(database)
            @database = database
          end

          def call(moves)
            statements = moves.flat_map { |move| RowMoves.statements(move) }
            @database.transaction { |batch| RowMoves.write(batch, statements) }
          end
        end
      end
    end
  end
end
