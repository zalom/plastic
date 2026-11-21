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

        # The session in one phrase, its times in `zone` or else the zone of the machine: when it ended and why, else its last turn.
        def summary(zone = nil)
          return "session #{session_id} ended #{Plastic.local(ended_at, zone)} (#{end_reason})" if ended?
          return "session #{session_id} started #{Plastic.local(started_at, zone)}, no turn recorded" if last_turn_at.to_s.empty?

          "session #{session_id} last turn #{Plastic.local(last_turn_at, zone)}"
        end
      end
    end
  end
end
