# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Releases a claimed or failed node back to open.
        class Release < MoveNode
          move :release_node
        end
      end
    end
  end
end
