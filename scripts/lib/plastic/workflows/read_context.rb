# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/retrieval_graph"
require_relative "context_readback"

module Plastic
  module Workflows
    # Reads the saved retrieval context of one intent with its evidence freshness.
    class ReadContext < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem

      forget_stop :problem

      read "read the saved context" do |context|
        context.row("context", ContextReadback.new(context).call)
      rescue Errno::ENOENT
        context[:problem] = "no retrieval context for intent #{context.intent_id}"
      rescue Graph::RetrievalGraph::MaintenanceRequired, Graph::RetrievalGraph::MissingReference, KeyError => error
        context[:problem] = error.message
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      outcome :done, offers: nil, because: "the retrieval context was read"
    end
  end
end
