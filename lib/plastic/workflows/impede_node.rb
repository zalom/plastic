# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to impeded, with the impediment.
    class ImpedeNode < MoveNode
      move :impede_node
    end
  end
end
