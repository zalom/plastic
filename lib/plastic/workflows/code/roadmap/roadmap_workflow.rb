# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # The base of the roadmap workflows that open on a roadmap that exists.
        # It sits in no registry and no command names it.
        class RoadmapWorkflow < CodeWorkflow
          # Stops the call, as a failure, when the roadmap named by the slug has no row.
          def self.roadmap_gate
            gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }
          end
        end
      end
    end
  end
end
