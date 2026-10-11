# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "document_lookup"
require_relative "retrieval_repair"

module Plastic
  module Workflows
    # Fetches one current or immutable document, or one bounded passage of it.
    class GetDocument < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem

      forget_stop :problem

      read "fetch the document" do |context|
        context.row("document", DocumentLookup.new(context).selected(context.reference, context.passage))
      rescue *DocumentLookup::FAILURES => error
        context[:problem] = RetrievalRepair.new(context.scope, error).problem
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      outcome :done, offers: nil, because: "the document was read"
    end
  end
end
