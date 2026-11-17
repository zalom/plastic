# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Resources
        # Moves the rows of the files a sort moves, in one transaction of the store: the documents, their heads and
        # revisions by path inside the intent, the kept files and the printed files by path inside the store.
        class RowMoves
          INTENT_FILE = %r{\Astore/([^/]*)--[^/]*/(.+)\z}
          BY_INTENT = %w[documents document_heads document_revisions].freeze
          BY_STORE = { "sqlar" => "name", "printed" => "path" }.freeze

          def initialize(database)
            @database = database
          end

          def call(moves, back: false)
            @database.transaction do |batch|
              moves.each { |move| statements(batch, back ? move.class.new(move.to, move.from) : move) }
            end
          end

          private

          def statements(batch, move)
            id, from = INTENT_FILE.match(move.from).captures
            to = INTENT_FILE.match(move.to).captures.last
            BY_INTENT.each { |table| batch.add("UPDATE OR REPLACE #{table} SET path = :to WHERE intent_id = :id AND path = :from", id:, from:, to:) }
            BY_STORE.each { |table, column| batch.add("UPDATE OR REPLACE #{table} SET #{column} = :to WHERE #{column} = :from", from: move.from, to: move.to) }
          end
        end
      end
    end
  end
end
