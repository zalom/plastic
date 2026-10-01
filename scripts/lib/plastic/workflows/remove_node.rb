# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Moves a node from open to removed.
    class RemoveNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :moved

      step "remove the node", done: ->(context) { !context.moved.nil? } do |context|
        node = context.work.remove_node(intent_id: context.intent_id, id: context.id, reason: context.reason)
        context[:moved] = !node.nil?
        context[:problem] = node ? nil : refusal(context)
      end

      def self.refusal(context)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal("removed") : "no node #{id} in intent #{intent_id}"
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "say what was removed" do |context|
        context.print("node: #{context.id} removed")
      end

      outcome :done, offers: "plastic graph ready %{intent_id}", because: "node %{id} is removed"
    end
  end
end
