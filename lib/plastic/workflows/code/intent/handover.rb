# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/work/completion/review"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes one `handed_over` work log line: the owner's word that a follow-up intent takes over the last gap of an
        # intent whose review rounds are used, so the intent can end. A missing intent or follow-up fails; a done or
        # abandoned intent, a follow-up that is the intent itself or abandoned, a round left and a second handover are refused.
        class Handover < CodeWorkflow
          clear_declarations
          summary "Hands the last gap of an intent whose review rounds are used to a follow-up intent, on the owner's word."
          sets :follow_up_intent

          open_intent_gates "hand over"

          read("read the follow-up") { |context| context[:follow_up_intent] = context.retrieval.intent(context.follow_up) }

          gate "no intent %{follow_up} in this store to take over the last gap of intent %{intent_id}", stops: :failure,
            pass: ->(context) { !context.follow_up_intent.nil? }
          gate "intent %{intent_id} cannot take over its own last gap; name another intent", stops: :refusal,
            pass: ->(context) { context.follow_up != context.intent_id }
          gate "intent %{follow_up} is abandoned, so it cannot take over the last gap of intent %{intent_id}", stops: :refusal,
            pass: ->(context) { context.follow_up_intent.status != "abandoned" }
          gate "intent %{intent_id} is already handed over", stops: :refusal,
            pass: ->(context) { !Plastic::Graph::Work::Completion::Review.of(context).handed_over? }
          gate "intent %{intent_id} still has a review round left or holds an accepted review; a handover needs the rounds used", stops: :refusal,
            pass: ->(context) { Plastic::Graph::Work::Completion::Review.of(context).used_up? }

          step "write the handover", done: ->(context) { Plastic::Graph::Work::Completion::Review.of(context).handed_over? },
            changes: { work: "The owner's handover of the last gap to the follow-up intent is written to the work log as one `handed_over` line" } do |context|
            context.work.hand_over(context.intent_id, context.follow_up, context.reason)
          end

          outcome :parked, if: ->(context) { context.intent.status == "parked" }, offers: "plastic intent start %{intent_id}",
            because: "intent %{intent_id} is parked; start it again to end it, now that intent %{follow_up} takes over its last gap"
          outcome :done, offers: "plastic intent end %{intent_id}", because: "intent %{follow_up} takes over the last gap of intent %{intent_id}, on the owner's word"
        end
      end
    end
  end
end
