# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/work/completion/check"
require_relative "delivery_ownership"

module Plastic
  module Workflows
    # Reads the intent and its lock: a missing or closed intent fails, a foreign live lock refuses, and an outcome without a Reverted line hands over the revert steps.
    class PrepareAbandon < CodeWorkflow
      sets :intent, :status, :problem, :intent_folder, :reverted

      read "read the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:status] = context.intent&.status
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
      gate "intent %{intent_id} is %{status}; it can no longer be abandoned", stops: :failure,
        pass: ->(context) { !%w[done abandoned].include?(context.status) }

      read "check delivery ownership" do |context|
        context[:problem] = DeliveryOwnership.problem(context)
        context[:intent_folder] = context.intent.dir
        context[:reverted] = Graph::Work::Completion::Check.new(context.retrieval, context.intent_id).verification.reverted?
      end

      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      outcome :reverting, if: ->(context) { !context.reverted }
      outcome :abandoning
    end
  end
end
