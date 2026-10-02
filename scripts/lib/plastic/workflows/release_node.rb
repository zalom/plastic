# frozen_string_literal: true

require_relative "move_node"

module Plastic
  module Workflows
    # Releases a claimed or failed node back to open.
    class ReleaseNode < MoveNode
      [facts, steps, outcomes].each(&:clear)

      move :release_node, state: "open", step_name: "release the node", say: "say what was released",
        result: { offers: "plastic node claim %{intent_id} %{id}", because: "node %{id} is open" }
    end
  end
end
