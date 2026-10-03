# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "release_update"

module Plastic
  module Workflows
    # Switches the active pointer to the named release or the previous one,
    # and syncs that release's files into the home in the same activation.
    class RollbackRelease < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :switched

      step "switch the active release", done: ->(context) { context.switched } do |context|
        activation = ReleaseUpdate.of(context).activation
        context[:switched] = activation.switch(context.target || activation.previous_version)
      end

      outcome :done, offers: "plastic version", because: "Plastic %{switched} is active and the home holds its files"
    end
  end
end
