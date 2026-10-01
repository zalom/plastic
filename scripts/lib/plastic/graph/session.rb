# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # One row of the home's `sessions` table: the harness run that made the
    # calls, from its first turn to the reason it ended.
    Session = Data.define(:session_id, :harness, :store, :directory, :started_at, :last_turn_at, :ended_at,
      :end_reason, :note) do
      include Record

      def ended? = !ended_at.nil?
    end
  end
end
