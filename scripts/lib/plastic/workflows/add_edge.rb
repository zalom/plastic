# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes one guarded edge: fails on a self edge, a missing or removed
    # node, or a loop back to its own start.
    class AddEdge < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :problem, :added

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      step "add the edge", done: ->(context) { !context.added.nil? } do |context|
        added = context.work.add_edge(intent_id: context.intent_id, from: context.from, to: context.to)
        context[:added] = added
        context[:problem] = added ? nil : "edge #{context.from} to #{context.to} would loop or names a missing node"
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "say what was added" do |context|
        context.print("edge: #{context.from} to #{context.to}")
      end

      outcome :done, offers: "plastic graph show %{intent_id}", because: "edge %{from} to %{to} is written"
    end
  end
end
