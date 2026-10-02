# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Answers a parked node's question, moving it back to open with its
    # retries reset.
    class AnswerNode < MoveNode
      move :answer_node
    end
  end
end
