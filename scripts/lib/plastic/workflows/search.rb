# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/retrieval_graph"
require_relative "search_query"

module Plastic
  module Workflows
    # Searches literal indexed passages in the selected local stores and
    # reports them as one fused list.
    class Search < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem

      forget_stop :problem

      read "search the indexed passages" do |context|
        context.row("rows", SearchQuery.new(context).rows)
      rescue Graph::RetrievalGraph::MaintenanceRequired => error
        context[:problem] = error.message
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      outcome :done, offers: nil, because: "the indexed passages were read"
    end
  end
end
