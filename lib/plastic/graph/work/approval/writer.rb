# frozen_string_literal: true

require_relative "../approval"

module Plastic
  module Graph
    module Work
      class Approval
        # Writes the go-ahead of an intent. A second call changes nothing.
        class Writer
          def initialize(databases, retrieval, clock:, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
            @clock = clock
          end

          def approve(intent_id) = @retrieval.structure.approval(intent_id) || insert(intent_id)

          private

          def insert(intent_id)
            @databases.fetch(:store).transaction { |batch| batch.put(:approvals, { intent_id:, at: Plastic.timestamp(@clock.now), session_id: @session }, statement: :insert) }
            @retrieval.structure.approval(intent_id)
          end
        end
      end
    end
  end
end
