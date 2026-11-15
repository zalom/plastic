# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # Opens a ready item's intent, its spec.md holding the batch and item's
        # goal and done criteria, then links the intent to the roadmap.
        class Open < CodeWorkflow
          clear_declarations

          sets :problem, :kind, :intent_id

          forget_stop :problem, :kind

          step "open the item's intent", done: ->(context) { !context.intent_id.nil? || !context.problem.nil? },
            changes: { work: "The item's intent is opened and the item points to it" } do |context|
            intent_id, problem, kind = context.work.open_roadmap_item(context.slug, context.item_id)
            context[:intent_id] = intent_id
            context[:problem] = problem
            context[:kind] = kind
          end

          gate "%{problem}", stops: :failure,
            words: "the roadmap has no such item",
            pass: ->(context) { context.kind != :failure }
          gate "%{problem}", stops: :refusal,
            words: "the item already has an intent, or a needed item is not done yet",
            pass: ->(context) { context.kind != :refusal }

          read "say what was opened" do |context|
            context.print("intent: #{context.intent_id}")
          end

          outcome :done, offers: "plastic intent brief %{intent_id}", because: "item %{item_id} opened as intent %{intent_id}"
        end
      end
    end
  end
end
