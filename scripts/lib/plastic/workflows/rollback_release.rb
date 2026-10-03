# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "release_update"

module Plastic
  module Workflows
    # Switches the active pointer to the named release or the previous one.
    # The files in the home stay as they are until a reinstall syncs them.
    class RollbackRelease < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :switched

      step "switch the active release", done: ->(context) { context.switched } do |context|
        activation = ReleaseUpdate.of(context).activation
        context[:switched] = activation.switch(context.target || activation.previous_version)
      end

      outcome :done, offers: "plastic install --reinstall",
        because: "Plastic %{switched} is active; reinstall to sync its files into the home"
    end
  end
end
