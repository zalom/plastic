# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "sync_steps"

module Plastic
  module Workflows
    # Sync down: plans, applies, and refuses on the conflicts left.
    class SyncDown < CodeWorkflow
      extend SyncSteps

      sync :down
    end
  end
end
