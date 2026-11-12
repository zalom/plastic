# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Moves a claimed node to failed, with a reason.
        class Fail < MoveNode
          move :fail_node
        end
      end
    end
  end
end
