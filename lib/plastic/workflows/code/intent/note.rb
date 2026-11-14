# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Adds a note line to the outcome of an intent.
        class Note < CodeWorkflow
          [facts, steps, outcomes].each(&:clear)

          CLOSED = %w[done abandoned].freeze

          sets :intent, :status, :problem, :reference

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its outcome", stops: :failure,
            offers: "plastic next", because: "a closed intent keeps its outcome; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

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
  end
end
