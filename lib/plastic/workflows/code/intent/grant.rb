# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/work/completion/review"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes one `granted` work log line, which adds one review round. A missing or closed intent fails; an intent that still has a round left, or holds an accepted review, is refused.
        class Grant < CodeWorkflow
          clear_declarations
          summary "Grants one extra review round to an intent whose rounds are used."

          sets :problem

          read "check the intent" do |context|
            context[:problem] = context.work.open_intent_problem(context.intent_id, "grant")
          end

          gate "%{problem}", stops: :failure, words: "the intent is missing, done or abandoned", pass: ->(context) { context.problem.nil? }
          gate "intent %{intent_id} still has a review round left or holds an accepted review; a grant needs the rounds used", stops: :refusal,
            pass: ->(context) { Plastic::Graph::Work::Completion::Review.of(context).used_up? }

          step "write the grant", done: ->(context) { context.work.rounds_left?(context.intent_id) },
            changes: { work: "One extra review round is granted" } do |context|
            context.work.grant_round(context.intent_id, context.reason)
          end

          outcome :done, offers: "plastic intent judge %{intent_id}", because: "intent %{intent_id} has one more review round, on the owner's word"
        end
      end
    end
  end
end
