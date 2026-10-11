# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "document_lookup"
require_relative "retrieval_repair"

module Plastic
  module Workflows
    # Fetches qualified documents in the exact request order.
    class BatchDocuments < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem

      forget_stop :problem

      read "fetch the documents" do |context|
        lookup = DocumentLookup.new(context)
        context.row("documents", context.references.split.map { |reference| lookup.fetch(reference) })
      rescue *DocumentLookup::FAILURES => error
        context[:problem] = RetrievalRepair.new(context.scope, error).problem
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      outcome :done, offers: nil, because: "the documents were read"
    end
  end
end
