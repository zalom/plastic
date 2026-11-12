# frozen_string_literal: true

require_relative "../approval"

module Plastic
  module Graph
    module Work
      class Approval
        # Writes the go-ahead of an intent. A second call changes nothing.
        class Writer
          def initialize(databases, retrieval, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
          end

          def approve(intent_id, at: Plastic.now) = @retrieval.approval(intent_id) || insert(intent_id, at)

          private

          def insert(intent_id, at)
            @databases.fetch(:work).transaction { |batch| batch.put(:approvals, { intent_id:, at:, session_id: @session }, statement: :insert) }
            @retrieval.approval(intent_id)
          end
        end
      end
    end
  end
end
