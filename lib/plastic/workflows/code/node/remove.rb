# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Moves a node from open to removed.
        class Remove < MoveNode
          move :remove_node
        end
      end
    end
  end
end
