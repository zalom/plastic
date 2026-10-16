# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Adds a note line to the outcome of an intent.
    class NoteIntent < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :problem, :reference

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "check the note" do |context|
        context[:problem] = context.work.note_problem(context.intent, context.text)
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      step "write the note", done: ->(context) { !context.reference.nil? } do |context|
        context[:reference] = context.work.note_intent(context.intent, context.kind, context.text)
      end

      read "say what was written" do |context|
        context.print("#{context.kind.downcase}: #{context.text}")
      end

      outcome :done, offers: nil, because: "the outcome holds the note"
    end
  end
end
