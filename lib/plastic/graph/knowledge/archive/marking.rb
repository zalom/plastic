# frozen_string_literal: true

require_relative "../archive"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # The row that marks an intent archived: the session that archived it and the time it was archived.
        Marking = Data.define(:session, :clock) do
          def row(intent) = { intent_id: intent.intent_id, at: Plastic.timestamp(clock.now), restored_at: nil, session_id: session }
        end
      end
    end
  end
end
