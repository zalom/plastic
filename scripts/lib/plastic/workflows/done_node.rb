# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Moves a claimed node to done, with its judge and findings.
    class DoneNode < MoveNode
      [facts, steps, outcomes].each(&:clear)

      move :done_node, state: "done", step_name: "finish the node", say: "say what was done",
        result: { offers: "plastic graph ready %{intent_id}", because: "node %{id} is done" } do |context|
        { judge: context.judge, findings: context.findings }
      end
    end
  end
end
