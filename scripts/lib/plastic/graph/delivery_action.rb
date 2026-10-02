# frozen_string_literal: true

module Plastic
  module Graph
    # The next concrete action for a delivery, or instructions for the harness.
    class DeliveryAction
      def initialize(retrieval, intent_id)
        @retrieval = retrieval
        @intent_id = intent_id
      end

      def call
        intent = @retrieval.intent(@intent_id)
        return ["none", "intent #{@intent_id} is closed", nil] unless intent.open?
        return planning if live.empty?
        return ["plastic intent end #{@intent_id}", "the nodes are done; verify the intent's criteria", nil] if live.all? { |node| node.state == "done" }

        pending_action
      end

      private

      def live = @live ||= @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }

      def planning
        [nil, "the harness must plan this intent", "Read the intent's goal and done criteria. Add work with " \
          "plastic node add #{@intent_id} TITLE --criterion TEXT, then add dependencies with plastic edge add. " \
          "Use plastic graph ready #{@intent_id} after the plan is recorded."]
      end

      def pending_action
        failed = live.find { |node| node.state == "failed" }
        return ["plastic node release #{@intent_id} #{failed.id}", "node #{failed.id} failed; release it before retrying", nil] if failed

        ready = @retrieval.ready_nodes(@intent_id).first
        return ["plastic node claim #{@intent_id} #{ready.id}", "node #{ready.id} is ready", nil] if ready

        waiting_action
      end

      def waiting_action
        parked = live.find { |node| node.state == "parked" }
        return parked_action(parked) if parked

        claimed = live.find { |node| node.state == "claimed" }
        return claimed_action(claimed) if claimed

        [nil, "dependencies block the remaining nodes", "Inspect plastic graph show #{@intent_id} and repair the dependencies " \
          "through edge commands before claiming more work."]
      end

      def parked_action(node)
        [nil, "the owner must answer node #{node.id}", "Ask the owner: #{node.question}. Record their answer with " \
          "plastic node answer #{@intent_id} #{node.id} --answer TEXT."]
      end

      def claimed_action(node)
        [nil, "node #{node.id} is already claimed", "Continue node #{node.id} with its worker #{node.by}. " \
          "Record the result with plastic node done #{@intent_id} #{node.id} --judge tests|tool|agent|owner --findings TEXT, " \
          "or record a failure with plastic node fail #{@intent_id} #{node.id} --reason TEXT."]
      end
    end
  end
end
