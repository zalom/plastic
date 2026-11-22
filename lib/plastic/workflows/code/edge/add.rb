# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Edge
        # Writes one guarded edge: fails on a self edge, a missing or removed
        # node, a duplicate edge, or a loop back to its own start, each with its own reason.
        class Add < CodeWorkflow
          clear_declarations

          sets :intent, :problem, :added

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read("forget a refusal of an earlier call") { |context| context[:added] = nil if context.added == false }

          step "add the edge", done: ->(context) { !context.added.nil? },
            changes: { work: "An edge between two nodes of the intent is added" } do |context|
            added, problem = context.work.add_edge(intent_id: context.intent_id, from: context.from, to: context.to)
            context[:added] = added
            context[:problem] = problem
          end

          gate "%{problem}", stops: :failure,
            words: "the edge is a self edge, a duplicate, would make a loop, or an end of the edge is not a live node of the intent",
            pass: ->(context) { context.problem.nil? }

          read "say what was added" do |context|
            context.print("edge: #{context.from} to #{context.to}")
          end

          outcome :done, offers: "plastic graph check %{intent_id}", because: "edge %{from} to %{to} is written; the check finds what the graph still lacks"
        end
      end
    end
  end
end
