# frozen_string_literal: true

require_relative "../node"

module Plastic
  module Graph
    module Work
      module Completion
        # The live work nodes of one intent: every one finished and verified before delivered closure.
        class WorkCheck
          def initialize(retrieval, intent_id)
            @retrieval = retrieval
            @intent_id = intent_id
          end

          def problem
            nodes = live_nodes
            return "Plan at least one work node with plastic node add #{@intent_id} TITLE --criterion KEY." if nodes.empty?

            unfinished_problem(nodes) || unverified_problem(nodes)
          end

          private

          def unfinished_problem(nodes)
            "Finish every live work node before ending intent #{@intent_id}." unless nodes.all? { |node| node.state == "done" }
          end

          def unverified_problem(nodes)
            return if nodes.all?(&:verified?)

            "Every done node needs nonempty findings. Recheck the work, then use plastic node done #{@intent_id} NODE " \
              "--repair --findings TEXT to record the actual verification."
          end

          def live_nodes = @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }
        end
      end
    end
  end
end
