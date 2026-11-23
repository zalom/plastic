# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/spec"
require_relative "../../../graph/work/start_check"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes the go-ahead row of an open or in progress intent, then prints the findings of its graph; none refuses.
        # A second call changes nothing.
        class Approve < CodeWorkflow
          clear_declarations

          open_intent_gates "go-ahead"

          gate "intent %{intent_id} names no done criterion", stops: :failure, offers: "plastic intent spec %{intent_id}",
            because: "an approval needs a done criterion to judge the delivery by; write one in spec.md",
            pass: ->(context) { !Plastic::Graph::Knowledge::Spec.new(context.retrieval, context.intent_id).done_criteria.empty? }

          step "write the go-ahead", done: ->(context) { !context.retrieval.structure.approval(context.intent_id).nil? },
            changes: { work: "The approval of the intent is recorded" } do |context|
            context.work.approve_intent(context.intent_id)
          end

          read "say what was written" do |context|
            context.print("approved: #{context.intent_id}")
            check = Plastic::Graph::Work::StartCheck.new(context.retrieval, context.retrieval.intent(context.intent_id), context.scope.root)
            check.lines.each { |line| context.print(line) }
          end

          outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} has the owner's go-ahead"
        end
      end
    end
  end
end
