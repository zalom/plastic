# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Reopens a needs_info or impeded node with its resolution and resets its
    # retries.
    class ResolveNode < MoveNode
      move :resolve_node
    end
  end
end
