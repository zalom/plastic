# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Moves a claimed node to needs_info, with the question for the owner.
        class Ask < MoveNode
          move :ask_node
        end
      end
    end
  end
end
