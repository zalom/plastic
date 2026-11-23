# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # A directed edge between two nodes. Only `needs` orders the work: `to`
      # waits until `from` is done. A `found_in` edge says `from` was found while doing `to`, and orders nothing.
      Edge = Data.define(:intent_id, :from, :to, :kind, :origin_id) do
        include Record

        # A need touches the two nodes it names. A found_in edge orders nothing, so it touches no node.
        def touches?(node_id) = needs? && ends.include?(node_id)

        def needs? = kind == "needs"

        def ends = [from, to]
      end
    end
  end
end
