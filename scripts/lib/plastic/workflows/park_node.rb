# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to parked, with a question for the owner.
    class ParkNode < MoveNode
      [facts, steps, outcomes].each(&:clear)

      move :park_node, state: "parked", step_name: "park the node", say: "say what was parked",
        result: { offers: "plastic node answer %{intent_id} %{id} --answer TEXT", because: "node %{id} is parked" } do |context|
        { question: context.question }
      end
    end
  end
end
