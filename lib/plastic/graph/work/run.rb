# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One claim of a node, from the moment a session took it until its result.
      # `number` counts the runs of the node; an open run has no `ended_at`.
      Run = Data.define(:intent_id, :node_id, :number, :agent, :session_id, :started_at, :ended_at, :result, :origin_id) do
        include Record

        def open? = ended_at.nil?
      end
    end
  end
end
