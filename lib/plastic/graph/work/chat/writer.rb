# frozen_string_literal: true

require_relative "../../../clock"

module Plastic
  module Graph
    module Work
      module Chat
        # The write side of the home's `chat_messages` table: one row for each message of a
        # session, in one short transaction. `store` is the project the session ran in, nil when none resolved.
        class Writer
          def initialize(home, store:, clock:)
            @home = home
            @store = store
            @clock = clock
          end

          def record(session_id:, harness:, intent_id:, role:, text:)
            row = { session_id:, harness:, store: @store, intent_id:, role:, at: Plastic.timestamp(@clock.now), text: }
            @home.transaction { |batch| batch.put(:chat_messages, row, statement: :insert) }
          end
        end
      end
    end
  end
end
