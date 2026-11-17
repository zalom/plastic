# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # A directed edge between two nodes. Only `needs` orders the work: `to`
      # waits until `from` is done.
      Edge = Data.define(:intent_id, :from, :to, :kind, :origin_id) do
        include Record

        def touches?(node_id) = from == node_id || to == node_id
      end
    end
  end
end
