# frozen_string_literal: true

require_relative "../context"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/retrieval_graph"
require_relative "../../../context_readback"
require_relative "../../../retrieval_repair"

module Plastic
  module Workflows
    module Code
      module Intent
        class Context
          # Reads the saved retrieval context of one intent with its evidence freshness.
          class Read < CodeWorkflow
            clear_declarations
            summary "Prints the saved retrieval context of the intent."

            sets :problem

            forget_stop :problem

            read "read the saved context" do |context|
              context.row("context", ContextReadback.new(context).call)
            rescue Errno::ENOENT
              context[:problem] = "no retrieval context for intent #{context.intent_id}"
            rescue Plastic::Graph::RetrievalGraph::MaintenanceRequired, Plastic::Graph::RetrievalGraph::MissingReference, KeyError => error
              context[:problem] = RetrievalRepair.new(context.scope, error).problem
            end

            gate "%{problem}", stops: :failure,
              words: "no retrieval context is saved, or a store needs repair",
              pass: ->(context) { context.problem.nil? }

            outcome :done, offers: nil, because: "the retrieval context was read"
          end
        end
      end
    end
  end
end
