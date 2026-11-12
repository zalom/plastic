# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Removes one edge; fails when no such edge exists.
    class RemoveEdge < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :removed

      read("forget a refusal of an earlier call") { |context| context[:removed] = nil if context.removed == false }

      step "remove the edge", done: ->(context) { !context.removed.nil? } do |context|
        removed = context.work.remove_edge(intent_id: context.intent_id, from: context.from, to: context.to)
        context[:removed] = removed
        context[:problem] = removed ? nil : "no edge #{context.from} to #{context.to} in intent #{context.intent_id}"
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "say what was removed" do |context|
        context.print("edge: #{context.from} to #{context.to} removed")
      end

      outcome :done, offers: "plastic graph show %{intent_id}", because: "edge %{from} to %{to} is gone"
    end
  end
end
