# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "sync_steps"

module Plastic
  module Workflows
    # Sync up: plans, applies, and refuses on the conflicts left.
    class SyncUp < CodeWorkflow
      extend SyncSteps

      sync :up
    end
  end
end
