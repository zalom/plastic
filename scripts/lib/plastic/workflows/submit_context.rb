# frozen_string_literal: true

require "json"
require_relative "../code_workflow"
require_relative "../graph/retrieval/context/source"
require_relative "../graph/retrieval_graph"
require_relative "context_documents"
require_relative "context_persistence"
require_relative "context_submission"
require_relative "retrieval_repair"

module Plastic
  module Workflows
    # Validates a submitted evidence selection and persists it in the owning store.
    class SubmitContext < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem

      forget_stop :problem

      read "persist the submitted context" do |context|
        discovery = ContextDocuments.new(context).read(:discovery)
        source = Graph::Retrieval::Context::Source.new(context.scope.plastic_home)
        submission = ContextSubmission.new(intent_id: context.intent_id, discovery:, source:).validate(context.from)
        context.row("context", ContextPersistence.new(context).persist(submission))
      rescue Errno::ENOENT, JSON::ParserError => error
        raise CLI::Command::Usage, error.message
      rescue Graph::RetrievalGraph::MaintenanceRequired, Graph::RetrievalGraph::MissingReference, KeyError, CLI::Command::Failure => error
        context[:problem] = RetrievalRepair.new(context.scope, error).problem
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      outcome :done, offers: nil, because: "the retrieval context was read"
    end
  end
end
