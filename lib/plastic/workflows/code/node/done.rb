# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Moves a claimed node to done, with its findings. A done node takes new findings in place of the old.
        class Done < MoveNode
          move :done_node
        end
      end
    end
  end
end
