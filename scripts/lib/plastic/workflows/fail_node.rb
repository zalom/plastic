# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to failed, with a reason.
    class FailNode < MoveNode
      [facts, steps, outcomes].each(&:clear)

      move :fail_node, state: "failed", step_name: "fail the node", say: "say what failed",
        result: { offers: "plastic node release %{intent_id} %{id}", because: "node %{id} is failed" } do |context|
        { reason: context.reason }
      end
    end
  end
end
