# frozen_string_literal: true

require "json"
require_relative "../../../code_workflow"
require_relative "../../../graph/retrieval/context/source"
require_relative "../../../graph/retrieval_graph"
require_relative "../../context_documents"
require_relative "../../context_persistence"
require_relative "../../context_submission"
require_relative "../../retrieval_repair"

module Plastic
  module Workflows
    module Code
      module Intent
        # Validates a submitted evidence selection and persists it in the owning store.
        class Context < CodeWorkflow
          clear_declarations
          summary "Validates the submitted evidence selection and saves it in the owning store."

          sets :problem

          forget_stop :problem

          def self.submission(context)
            discovery = ContextDocuments.new(context).read(:discovery)
            source = Plastic::Graph::Retrieval::Context::Source.new(context.scope.plastic_home)
            ContextSubmission.new(intent_id: context.intent_id, discovery:, source:).validate(context.from)
          end

          read "validate the submitted context" do |context|
            submission(context)
          rescue Errno::ENOENT, JSON::ParserError => error
            raise Usage, error.message
          rescue Plastic::Graph::RetrievalGraph::MaintenanceRequired, Plastic::Graph::RetrievalGraph::MissingReference, KeyError, Failed => error
            context[:problem] = RetrievalRepair.new(context.scope, error).problem
          end

          gate "%{problem}", stops: :failure,
            words: "the submission is not valid, or a store needs repair",
            pass: ->(context) { context.problem.nil? }

          step "save the submitted context", done: ->(context) { ContextPersistence.new(context).saved?(submission(context)) },
            changes: { knowledge: "The submitted context is saved as a document of the intent, unless the same document is saved already" } do |context|
            ContextPersistence.new(context).persist(submission(context))
          end

          read("print the saved context") { |context| context.row("context", submission(context)) }

          outcome :done, offers: nil, because: "the submitted retrieval context is saved"
        end
      end
    end
  end
end
