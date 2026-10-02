# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to done, with its judge and findings.
    class DoneNode < MoveNode
      move :done_node
    end
  end
end
