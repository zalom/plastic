# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One row of the home's `sessions` table: the harness run that made the
      # calls, from its first turn to the reason it ended.
      Session = Data.define(:session_id, :harness, :store, :directory, :started_at, :last_turn_at, :ended_at,
        :end_reason, :note) do
        include Record

        def ended? = !ended_at.to_s.empty?

        # The session in one phrase: when it ended and why, else its last turn.
        def summary = ended? ? "session #{session_id} ended #{ended_at} (#{end_reason})" : "session #{session_id} last turn #{last_turn_at}"
      end
    end
  end
end
