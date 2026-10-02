# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Answers a parked node's question, moving it back to open with its
    # retries reset.
    class AnswerNode < MoveNode
      [facts, steps, outcomes].each(&:clear)

      move :answer_node, state: "open", step_name: "answer the node", say: "say what was answered",
        result: { offers: "plastic node claim %{intent_id} %{id}", because: "node %{id} is open" } do |context|
        { answer: context.answer }
      end
    end
  end
end
