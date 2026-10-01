# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Claims an open node. The fourth claim of a node parks it instead, with
    # the owner's question, and refuses.
    class ClaimNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      STOPPED = %i[refused capped].freeze

      sets :result, :node, :problem

      step "claim the node", done: ->(context) { !context.result.nil? } do |context|
        result, node = context.work.claim_node(intent_id: context.intent_id, id: context.id, by: context.session)
        context[:result] = result
        context[:node] = node
        context[:problem] = problem_for(context, node)
      end

      def self.problem_for(context, node)
        intent_id, id = context.intent_id, context.id
        case context.result
        when :refused then node ? node.refusal("claimed") : "no node #{id} in intent #{intent_id}"
        when :capped then "node #{id} claimed 3 times; the owner decides"
        end
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { !STOPPED.include?(context.result) }

      read "print the brief" do |context|
        node = context.node
        context.print("node: #{node.id} #{node.title}")
        context.print("criterion: #{node.criterion}")
        context.print("input: #{node.input}") if node.input
        context.print("last findings: #{node.findings}") if node.findings
        context.print("last reason: #{node.reason}") if node.reason
      end

      outcome :done, offers: "plastic node done %{intent_id} %{id} --judge tests --findings TEXT",
        because: "node %{id} is claimed"
    end
  end
end
