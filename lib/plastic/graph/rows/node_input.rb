# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One input path of a node: the file the node reads. `position` counts the paths of the node from 1, in the order given.
      NodeInput = Data.define(:intent_id, :node_id, :position, :path, :origin_id) do
        include Record
      end
    end
  end
end
