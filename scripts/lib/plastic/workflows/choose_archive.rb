# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Only an explicit --revert selects restoration.
    class ChooseArchive < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      outcome :revert, if: ->(context) { context.revert }, because: "restoration was requested"
      outcome :archive, because: "archive was requested"
    end
  end
end
