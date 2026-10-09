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
        intent = context.retrieval.intent(context.intent_id)
        context[:problem] = intent_problem(intent, context.intent_id) || criterion_problem(context)
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
        spec = Graph::Knowledge::Spec.new(context.retrieval, context.intent_id)
        return "intent #{context.intent_id} has no synced spec.md; write its done criteria, then run plastic sync up" unless spec.present?

        keys = spec.criteria_by_key.keys
        return nil if keys.include?(context.criterion)

        "criterion #{context.criterion.inspect} is not a done criterion key of spec.md; the keys are: #{keys.join(", ")}"
      end

      def self.intent_problem(intent, intent_id)
        return "no intent #{intent_id} in this store" unless intent

        status = intent.status
        "intent #{intent_id} is #{status}; it takes no nodes" if %w[done abandoned].include?(status)
      end

      outcome :done, offers: "plastic node claim %{intent_id} %{id}", because: "node %{id} is open"
    end
  end
end
