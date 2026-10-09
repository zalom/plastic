# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/work/completion/review"

module Plastic
  module Workflows
    # Reads the intent and its judge rounds: a missing or closed intent fails, both rounds used is the owner's step.
    class PrepareJudge < CodeWorkflow
      sets :problem

      read "check the intent" do |context|
        context[:problem] = context.work.open_intent_problem(context.intent_id, "verdict")
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }
      gate "the judge's review round of intent %{intent_id} is used; the owner decides between abandoning the intent and a follow-up intent", stops: :refusal,
        pass: ->(context) { !Graph::Work::Completion::Review.of(context).used_up? }

      outcome :accepted, if: ->(context) { Graph::Work::Completion::Review.of(context).counting? }, offers: "plastic intent end %{intent_id}",
        because: "intent %{intent_id} is accepted"
      outcome :judging
    end
  end
end
