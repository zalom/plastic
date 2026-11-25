# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/ruling_order"
require_relative "../../lines"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes one decision, an addition to one, or a rewrite of one; fails on an unknown intent, or when --adds or
        # --rewrites names no decision of the intent. A rewrite names the additions it removed.
        class Rule < CodeWorkflow
          clear_declarations

          sets :intent, :problem, :id, :written, :removed

          forget_stop :problem, :id, :written

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "find the additions a rewrite removes" do |context|
            rewrites = context.rewrites
            context[:removed] = rewrites ? Plastic::Graph::Knowledge::RulingOrder.additions(context.retrieval.rulings(context.intent_id), rewrites).map(&:id) : []
          end

          step "write the decision", done: ->(context) { !context.problem.nil? || !context.id.nil? },
            changes: { knowledge: "The decision is added to the rulings of the intent, or its text is replaced and its additions removed" } do |context|
            named = context.adds || context.rewrites
            ruling = context.work.add_ruling(intent_id: context.intent_id, text: context.text, adds: context.adds, rewrites: context.rewrites)
            context[:id] = ruling&.id
            context[:written] = ruling&.text
            context[:problem] = ruling ? nil : "no decision #{named} in intent #{context.intent_id}"
          end

          gate "%{problem}", stops: :failure,
            words: "the decision to add to or to rewrite does not exist in the intent",
            pass: ->(context) { context.problem.nil? }

          read "say what was written" do |context|
            context.print("#{context.id}: #{context.written}")
            removed = context.removed
            context.print("removed: the #{(removed.size == 1) ? "addition" : "additions"} #{Lines.joined(removed)}") unless removed.empty?
          end

          outcome :done, offers: "plastic intent brief %{intent_id}", because: "decision %{id} is on record"
        end
      end
    end
  end
end
