# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"

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

      gate "intent %{intent_id} names no done criterion", stops: :failure, offers: "plastic intent spec %{intent_id}",
        because: "an approval needs a done criterion to judge the delivery by; write one in spec.md",
        pass: ->(context) { !Graph::Knowledge::Spec.new(context.retrieval, context.intent_id).done_criteria.empty? }

      step "write the go-ahead", done: ->(context) { !context.retrieval.approval(context.intent_id).nil? } do |context|
        context.work.approve_intent(context.intent_id)
      end

      read "say what was written" do |context|
        context.print("approved: #{context.intent_id}")
      end

      outcome :done, offers: "plastic auto %{intent_id}", because: "intent %{intent_id} has the owner's go-ahead"
    end
  end
end
