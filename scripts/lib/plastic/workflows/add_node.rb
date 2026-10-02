# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes a new node, open and ready, unless the intent is done or
    # abandoned.
    class AddNode < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :id

      read "check the intent" do |context|
        intent = context.retrieval.intent(context.intent_id)
        context[:problem] = intent_problem(intent, context.intent_id)
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

      def self.intent_problem(intent, intent_id)
        return "no intent #{intent_id} in this store" unless intent

        status = intent.status
        "intent #{intent_id} is #{status}; it takes no nodes" if %w[done abandoned].include?(status)
      end

      outcome :done, offers: "plastic node claim %{intent_id} %{id}", because: "node %{id} is open"
    end
  end
end
