# frozen_string_literal: true

require_relative "../node"

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
            return [plan_problem, uncovered_problem(nodes)].compact if nodes.empty?

            node_problem = unfinished_problem(nodes) || unverified_problem(nodes)
            node_problem ? [node_problem] : [uncovered_problem(nodes), orphan_problem(nodes)].compact
          end

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

          def uncovered_problem(nodes)
            missing = @keys - nodes.map(&:criterion)
            "Cover every done criterion with a done node. No done node serves: #{missing.join(", ")}." if missing.any?
          end

          def orphan_problem(nodes)
            stray = nodes.reject { |node| @keys.include?(node.criterion) }
            return if @keys.empty? || stray.empty?

            "Node #{stray.map { |node| "#{node.id} (#{node.criterion || "no key"})" }.join(", ")} names a criterion key that spec.md no longer has. " \
              "Fix the spec or replace the node."
          end

          def live_nodes = @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }
        end
      end
    end
  end
end
