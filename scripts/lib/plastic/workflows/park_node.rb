# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Moves a claimed node to parked, with a question for the owner.
    class ParkNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :moved

      step "park the node", done: ->(context) { !context.moved.nil? } do |context|
        node = context.work.park_node(intent_id: context.intent_id, id: context.id, question: context.question)
        context[:moved] = !node.nil?
        context[:problem] = node ? nil : refusal(context)
      end

      def self.refusal(context)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal("parked") : "no node #{id} in intent #{intent_id}"
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "say what was parked" do |context|
        context.print("node: #{context.id} parked")
      end

      outcome :done, offers: "plastic node answer %{intent_id} %{id} --answer TEXT", because: "node %{id} is parked"
    end
  end
end
