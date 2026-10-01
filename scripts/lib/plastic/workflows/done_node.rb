# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Moves a claimed node to done, with its judge and findings.
    class DoneNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :moved

      step "finish the node", done: ->(context) { !context.moved.nil? } do |context|
        node = context.work.done_node(intent_id: context.intent_id, id: context.id, judge: context.judge,
          findings: context.findings)
        context[:moved] = !node.nil?
        context[:problem] = node ? nil : refusal(context)
      end

      def self.refusal(context)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal("done") : "no node #{id} in intent #{intent_id}"
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      read "say what was done" do |context|
        context.print("node: #{context.id} done")
      end

      outcome :done, offers: "plastic graph ready %{intent_id}", because: "node %{id} is done"
    end
  end
end
