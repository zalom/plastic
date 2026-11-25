# frozen_string_literal: true

require_relative "../../rows/verdict"
require_relative "rounds"

module Plastic
  module Graph
    module Work
      class Verdict
        # Writes the next judge round of an intent. Returns the new row, or
        # nil when every round is already used.
        class Writer
          def initialize(databases, retrieval, clock:, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
            @clock = clock
          end

          def add_verdict(intent_id:, **fields)
            round = @retrieval.structure.verdicts(intent_id).size + 1
            insert({ intent_id:, round:, at: Plastic.timestamp(@clock.now), session_id: @session, **fields }) if rounds(intent_id).left?
          end

          def rounds_left?(intent_id) = rounds(intent_id).left?

          private

          def rounds(intent_id) = Rounds.new(@retrieval, intent_id)

          def insert(row)
            @databases.fetch(:store).transaction { |batch| batch.put(:verdicts, row, statement: :insert) }
            @retrieval.structure.verdicts(row[:intent_id]).find { |found| found.round == row[:round] }
          end
        end
      end
    end
  end
end
