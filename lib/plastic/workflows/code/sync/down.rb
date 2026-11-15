# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../sync_steps"

module Plastic
  module Workflows
    module Code
      module Sync
        # Sync down: plans, applies, and refuses on the conflicts left.
        class Down < CodeWorkflow
          extend SyncSteps

          sync :down
          summary "Writes the rows that changed into files."
        end
      end
    end
  end
end
