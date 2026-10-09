# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to done, with its findings.
    class DoneNode < MoveNode
      move :done_node

      def self.run_move(context, verb, shape)
        super(context, context.repair ? :repair_done_node : verb, shape)
      end
    end
  end
end
