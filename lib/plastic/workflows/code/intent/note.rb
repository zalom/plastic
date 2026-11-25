# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/intent/notes"

module Plastic
  module Workflows
    module Code
      module Intent
        # Adds a note line to the outcome of an intent.
        class Note < CodeWorkflow
          clear_declarations

          CLOSED = %w[done abandoned].freeze

          sets :intent, :status, :note_kind, :problem, :reference

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its outcome", stops: :refusal,
            offers: "plastic next", because: "a closed intent keeps its outcome; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

          read "check the note" do |context|
            context[:note_kind] = Plastic::Graph::Knowledge::Intent::Notes.kind(context.kind)
            context[:problem] = context.work.note_problem(context.note_kind.label, context.text)
          end

          gate "%{problem}", stops: :failure,
            words: "the note holds a line break, or a Verification line is not in its form",
            pass: ->(context) { context.problem.nil? }

          step "write the note", done: ->(context) { !context.reference.nil? },
            changes: { knowledge: "The line is added to the Notes or the Verification section of the outcome" } do |context|
            context[:reference] = context.work.note_intent(context.intent, context.note_kind.label, context.text)
          end

          read "say what was written" do |context|
            context.print("#{context.note_kind.label.downcase}: #{context.text}")
          end

          outcome :done, offers: "plastic next", because: "the outcome holds the note"
        end
      end
    end
  end
end
