# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Moves a claimed node to failed, with a reason.
    class FailNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :moved

      step "fail the node", done: ->(context) { !context.moved.nil? } do |context|
        node = context.work.fail_node(intent_id: context.intent_id, id: context.id, reason: context.reason)
        context[:moved] = !node.nil?
        context[:problem] = node ? nil : refusal(context)
      end

      def self.refusal(context)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal("failed") : "no node #{id} in intent #{intent_id}"
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "say what failed" do |context|
        context.print("node: #{context.id} failed")
      end

      outcome :done, offers: "plastic node release %{intent_id} %{id}", because: "node %{id} is failed"
    end
  end
end
