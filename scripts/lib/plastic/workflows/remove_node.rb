# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a node from open to removed.
    class RemoveNode < MoveNode
      [facts, steps, outcomes].each(&:clear)

      move :remove_node, state: "removed", step_name: "remove the node", say: "say what was removed",
        result: { offers: "plastic graph ready %{intent_id}", because: "node %{id} is removed" } do |context|
        { reason: context.reason }
      end
    end
  end
end
