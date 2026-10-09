# frozen_string_literal: true

require_relative "../verdict"

module Plastic
  module Graph
    module Work
      class Verdict
        # Writes the next judge round of an intent. Returns the new row, or
        # nil when both rounds are already used.
        class Writer
          def initialize(databases, retrieval, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
          end

          def add_verdict(intent_id:, at: Plastic.now, **fields)
            round = @retrieval.verdicts(intent_id).size + 1
            insert({ intent_id:, round:, at:, session_id: @session, **fields }) unless round > Verdict::ROUNDS
          end

          def rounds_left?(intent_id) = @retrieval.verdicts(intent_id).size < Verdict::ROUNDS

          private

          def insert(row)
            @databases.fetch(:work).transaction { |batch| batch.put(:verdicts, row, statement: :insert) }
            @retrieval.verdicts(row[:intent_id]).find { |found| found.round == row[:round] }
          end
        end
      end
    end
  end
end
