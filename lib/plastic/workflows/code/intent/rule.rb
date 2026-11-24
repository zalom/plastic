# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes one ruling; fails on an unknown intent, or when --supersedes
        # names no such ruling.
        class Rule < CodeWorkflow
          clear_declarations

          sets :intent, :problem, :id, :written

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          step "write the ruling", done: ->(context) { !context.problem.nil? || !context.id.nil? },
            changes: { knowledge: "The ruling is added to the rulings of the intent" } do |context|
            ruling = context.work.add_ruling(intent_id: context.intent_id, text: context.text, supersedes: context.supersedes)
            context[:id] = ruling&.id
            context[:written] = ruling&.text
            context[:problem] = ruling ? nil : "no ruling #{context.supersedes} in intent #{context.intent_id}"
          end

          gate "%{problem}", stops: :failure,
            words: "the ruling to supersede does not exist in the intent",
            pass: ->(context) { context.problem.nil? }

          read "say what was written" do |context|
            context.print("ruling: #{context.id} #{context.written}")
          end

          outcome :done, offers: "plastic intent brief %{intent_id}", because: "ruling %{id} is on record"
        end
      end
    end
  end
end
