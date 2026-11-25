# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Moves a claimed node to impeded, with the impediment.
        class Impede < MoveNode
          move :impede_node
        end
      end
    end
  end
end
