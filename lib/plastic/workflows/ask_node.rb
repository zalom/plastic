# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to needs_info, with the question for the owner.
    class AskNode < MoveNode
      move :ask_node
    end
  end
end
