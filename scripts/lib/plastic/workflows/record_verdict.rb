# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/work/verdict"

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

      gate "the review round is used: intent %{intent_id} was sent back twice, and the owner takes the next step", stops: :refusal,
        pass: ->(context) { !(latest(context).verdict == "revise" && latest(context).round >= Graph::Work::Verdict::ROUNDS) }

      outcome :revise, if: ->(context) { latest(context).verdict == "revise" }, offers: "plastic node add %{intent_id} TITLE --criterion KEY",
        because: "the judge asked for a revision; add a node that fixes it"
      outcome :accepted, offers: "plastic intent end %{intent_id}", because: "intent %{intent_id} is accepted"
    end
  end
end
