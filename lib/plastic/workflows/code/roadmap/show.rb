# frozen_string_literal: true

require_relative "roadmap_workflow"
require_relative "../../roadmap_print"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # Prints each batch with its goal and done criteria, then each item with
        # its derived state, from the rows.
        class Show < RoadmapWorkflow
          clear_declarations

          roadmap_gate

          read "print each batch and item" do |context|
            RoadmapPrint.call(context)
          end

          outcome :done, offers: "plastic roadmap next %{slug}", because: "the rows hold this roadmap"
        end
      end
    end
  end
end
