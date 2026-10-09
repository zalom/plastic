# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/work/verdict"
require_relative "../graph/work/completion/review"

module Plastic
  module Workflows
    # Writes the verdict row of the next review round. A second revise ends the call as the owner's step.
    class RecordVerdict < CodeWorkflow
      sets :rounds_before

      read("count the rounds written so far") { |context| context[:rounds_before] = context.retrieval.verdicts(context.intent_id).size }

      step "write the verdict", done: ->(context) { context.retrieval.verdicts(context.intent_id).size > context.rounds_before } do |context|
        context.work.add_verdict(intent_id: context.intent_id, verdict: context.verdict, findings: context.findings)
        context.work.print_intent(context.intent_id)
        context.print("verdict: #{context.verdict} round #{context.retrieval.verdicts(context.intent_id).size}")
      end

      def self.latest(context) = context.retrieval.verdicts(context.intent_id).max_by(&:round)

      gate "the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent", stops: :refusal,
        pass: ->(context) { !Graph::Work::Completion::Review.of(context).used_up? }

      outcome :revise, if: ->(context) { latest(context).verdict == "revise" }, offers: "plastic node add %{intent_id} TITLE --criterion KEY",
        because: "the judge asked for a revision; add a node that fixes it"
      outcome :accepted, offers: "plastic intent end %{intent_id}", because: "intent %{intent_id} is accepted"
    end
  end
end
