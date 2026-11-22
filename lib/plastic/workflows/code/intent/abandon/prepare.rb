# frozen_string_literal: true

require_relative "../abandon"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/work/completion/check"
require_relative "../../../delivery_ownership"

module Plastic
  module Workflows
    module Code
      module Intent
        class Abandon
          # Reads the intent and its claims: a missing or closed intent fails, a foreign live claim refuses, and a started intent whose outcome has no Reverted line hands over the revert steps.
          class Prepare < CodeWorkflow
            UNSTARTED = %w[future open].freeze

            summary "Reads the intent and its claims and checks that it can be abandoned."
            sets :intent, :status, :problem, :intent_folder, :reverted

            read "read the intent" do |context|
              context[:intent] = context.retrieval.intent(context.intent_id)
              context[:status] = context.intent&.status
            end

            gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
            gate "intent %{intent_id} is %{status}; it can no longer be abandoned", stops: :refusal,
              pass: ->(context) { !%w[done abandoned].include?(context.status) }

            read "check delivery ownership" do |context|
              context[:problem] = DeliveryOwnership.problem(context)
              context[:intent_folder] = context.intent.dir
              context[:reverted] = unstarted?(context) || Plastic::Graph::Work::Completion::Check.new(context.retrieval, context.intent_id).verification.reverted?
            end

            gate "%{problem}", stops: :refusal,
              words: "another live session holds a node claim of the intent",
              pass: ->(context) { context.problem.nil? }

            outcome :reverting, if: ->(context) { !context.reverted }, because: "the work of the intent is not reverted yet"
            outcome :abandoning, because: "no work of the intent is left to revert, so the intent can be marked abandoned"

            # A future or open intent with no node has no work to revert.
            def self.unstarted?(context)
              UNSTARTED.include?(context.status) && context.retrieval.structure.nodes(context.intent_id).empty?
            end
          end
        end
      end
    end
  end
end
