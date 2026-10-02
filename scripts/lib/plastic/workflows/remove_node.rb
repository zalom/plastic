# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a node from open to removed.
    class RemoveNode < MoveNode
      move :remove_node
    end
  end
end
