# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Releases a claimed or failed node back to open.
    class ReleaseNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :moved

      step "release the node", done: ->(context) { !context.moved.nil? } do |context|
        node = context.work.release_node(intent_id: context.intent_id, id: context.id)
        context[:moved] = !node.nil?
        context[:problem] = node ? nil : refusal(context)
      end

      def self.refusal(context)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal("open") : "no node #{id} in intent #{intent_id}"
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "say what was released" do |context|
        context.print("node: #{context.id} open")
      end

      outcome :done, offers: "plastic node claim %{intent_id} %{id}", because: "node %{id} is open"
    end
  end
end
