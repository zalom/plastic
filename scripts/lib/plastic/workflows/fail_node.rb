# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to failed, with a reason.
    class FailNode < MoveNode
      move :fail_node
    end
  end
end
