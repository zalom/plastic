# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes the go-ahead row of an open or active intent. A second call changes nothing.
    class ApproveIntent < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem

      read "check the intent" do |context|
        context[:problem] = context.work.open_intent_problem(context.intent_id, "go-ahead")
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      step "write the go-ahead", done: ->(context) { !context.retrieval.approval(context.intent_id).nil? } do |context|
        context.work.approve_intent(context.intent_id)
        context.work.print_intent(context.intent_id)
      end

      read "say what was written" do |context|
        context.print("approved: #{context.intent_id}")
      end

      outcome :done, offers: "plastic auto %{intent_id}", because: "intent %{intent_id} has the owner's go-ahead"
    end
  end
end
