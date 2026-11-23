# frozen_string_literal: true

require_relative "../../rows/node"
require_relative "stray_nodes"

module Plastic
  module Graph
    module Work
      module Completion
        # The live work nodes of one intent: every one finished and verified, and every done criterion covered by a done node.
        class WorkCheck
          def initialize(retrieval, intent_id, keys)
            @retrieval = retrieval
            @intent_id = intent_id
            @keys = keys
          end

          def problems
            nodes = live_nodes
            blocking = blocking_problem(nodes)
            return [blocking] if blocking && nodes.any?

            [blocking, uncovered_problem(nodes), orphan_problem(nodes)].compact
          end

          # The done criterion keys no live done node serves. `plastic intent end`, `intent judge` and `intent verdict` read this one answer.
          def uncovered_keys = @keys - live_nodes.select { |node| node.state == "done" }.map(&:criterion)

          private

          def plan_problem = "Plan at least one work node with plastic node add #{@intent_id} TITLE --criterion KEY."

          def unfinished_problem(nodes)
            "Finish every live work node before ending intent #{@intent_id}." unless nodes.all? { |node| node.state == "done" }
          end

          def unverified_problem(nodes)
            return if nodes.all?(&:verified?)

            "Every done node needs nonempty findings. Recheck the work, then use plastic node done #{@intent_id} NODE " \
              "TEXT to record the actual verification."
          end

          def blocking_problem(nodes) = nodes.empty? ? plan_problem : unfinished_problem(nodes) || unverified_problem(nodes)

          def uncovered_problem(_nodes) = uncovered_keys.join(", ").then { |list| "Cover every done criterion with a done node. No done node serves: #{list}." unless list.empty? }

          def orphan_problem(nodes) = (stray_text(nodes) if @keys.any?)

          def stray_text(nodes) = StrayNodes.message(nodes, @keys)

          def live_nodes = @retrieval.structure.nodes(@intent_id).select(&:live?)
        end
      end
    end
  end
end
