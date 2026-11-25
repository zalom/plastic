# frozen_string_literal: true

require_relative "../graph/work/completion/review"

module Plastic
  module Workflows
    # The gate that stops a workflow once the judge's review round of the intent is used.
    module ReviewRound
      MESSAGE = "the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent with plastic intent abandon %{intent_id}, a follow-up intent with plastic intent handover %{intent_id} FOLLOW_UP REASON --owner, and one more round with plastic intent grant %{intent_id} REASON --owner"

      def review_round_gate = gate(MESSAGE, stops: :refusal, pass: ->(context) { !Graph::Work::Completion::Review.of(context).used_up? })
    end
  end
end
