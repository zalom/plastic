# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"

module Plastic
  module Workflows
    # Writes a new node, open and ready, unless the intent is done or
    # abandoned.
    class AddNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :id

      read "check the intent" do |context|
        context[:problem] = context.work.open_intent_problem(context.intent_id, "nodes") || criterion_problem(context)
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      step "add the node", done: ->(context) { !context.id.nil? } do |context|
        node = context.work.add_node(intent_id: context.intent_id, title: context.title, criterion: context.criterion,
          input: context.input)
        context[:id] = node.id
      end

      read "say what was added" do |context|
        context.print("node: #{context.id}")
      end

      def self.criterion_problem(context)
        intent_id = context.intent_id
        spec = Graph::Knowledge::Spec.new(context.retrieval, intent_id)
        return "intent #{intent_id} has no synced spec.md; write its done criteria, then run plastic sync up" unless spec.present?

        key_problem(spec.criteria_by_key.keys, context.criterion)
      end

      def self.key_problem(keys, criterion)
        "criterion #{criterion.inspect} is not a done criterion key of spec.md; the keys are: #{keys.join(", ")}" unless keys.include?(criterion)
      end

      outcome :done, offers: "plastic node claim %{intent_id} %{id}", because: "node %{id} is open"
    end
  end
end
