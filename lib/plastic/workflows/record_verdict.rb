# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/work/verdict"
require_relative "../graph/work/completion/review"
require_relative "review_round"

module Plastic
  module Workflows
    # Writes the verdict row of the next review round. A second revise ends the call as the owner's step.
    class RecordVerdict < CodeWorkflow
      extend ReviewRound

      sets :rounds_before

      read("count the rounds written so far") { |context| context[:rounds_before] = context.retrieval.verdicts(context.intent_id).size }

      step "write the verdict", done: ->(context) { rounds(context) > context.rounds_before } do |context|
        context.work.add_verdict(intent_id: context.intent_id, verdict: context.verdict, findings: context.findings)
        context.print("verdict: #{context.verdict} round #{rounds(context)}")
      end

      def self.rounds(context) = context.retrieval.verdicts(context.intent_id).size

      def self.latest(context) = context.retrieval.verdicts(context.intent_id).max_by(&:round)

      review_round_gate

      outcome :revise, if: ->(context) { latest(context).verdict == "revise" }, offers: "plastic node add %{intent_id} TITLE --criterion KEY",
        because: "the judge asked for a revision; add a node that fixes it"
      outcome :accepted, offers: "plastic intent end %{intent_id}", because: "intent %{intent_id} is accepted"
    end
  end
end
