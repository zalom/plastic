# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Opens a ready item's intent, its spec.md holding the batch and item's
    # goal and done criteria, then links the intent to the roadmap.
    class StartRoadmapItem < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :kind, :intent_id

      forget_stop :problem, :kind

      step "open the item's intent", done: ->(context) { !context.intent_id.nil? || !context.problem.nil? } do |context|
        intent_id, problem, kind = context.work.start_roadmap_item(context.slug, context.item_id)
        context[:intent_id] = intent_id
        context[:problem] = problem
        context[:kind] = kind
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.kind != :failure }
      gate "%{problem}", stops: :refusal, pass: ->(context) { context.kind != :refusal }

      read "say what was opened" do |context|
        context.print("intent: #{context.intent_id}")
      end

      outcome :done, offers: "plastic intent brief %{intent_id}", because: "item %{item_id} opened as intent %{intent_id}"
    end
  end
end
