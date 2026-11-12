# frozen_string_literal: true

require_relative "../../move_node"

module Plastic
  module Workflows
    module Code
      module Node
        # Reopens a needs_info or impeded node with its resolution and resets its
        # retries.
        class Resolve < MoveNode
          move :resolve_node
        end
      end
    end
  end
end
