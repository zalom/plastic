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

          def add_verdict(intent_id:, verdict:, findings:, at: Plastic.now)
            round = @retrieval.verdicts(intent_id).size + 1
            return nil if round > Verdict::ROUNDS

            row = { intent_id:, round:, verdict:, findings:, at:, session_id: @session }
            @databases.fetch(:work).transaction { |batch| batch.put(:verdicts, row, statement: :insert) }
            @retrieval.verdicts(intent_id).find { |found| found.round == round }
          end
        end
      end
    end
  end
end
