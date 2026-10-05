# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # Removes the files Plastic registered with the chosen agents and keeps
    # the home with its stores.
    class UninstallPlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :removed

      step "remove the agent files", done: ->(context) { context.removed } do |context|
        installation = Installation.of(context)
        selected = Installation.selected(context)
        Installation.capture { installation.handle_uninstall(selected) }.each { |line| context.print(line) }
        context[:removed] = true
      end

      outcome :done, offers: "plastic install", because: "Plastic is removed from the chosen agents; the home stays"
    end
  end
end
