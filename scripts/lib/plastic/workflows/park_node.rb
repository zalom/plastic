# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to parked, with a question for the owner.
    class ParkNode < MoveNode
      move :park_node
    end
  end
end
