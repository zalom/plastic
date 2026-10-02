# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Releases a claimed or failed node back to open.
    class ReleaseNode < MoveNode
      move :release_node
    end
  end
end
