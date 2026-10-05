# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"
require_relative "release_removal"

module Plastic
  module Workflows
    # Removes the files Plastic registered with the chosen agents, then the
    # releases and the launcher once no agent stays registered. The home
    # with its stores stays.
    class UninstallPlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :removed, :releases_removed

      step "remove the agent files", done: ->(context) { context.removed } do |context|
        installation = Installation.of(context)
        selected = Installation.selected(context)
        Installation.capture { installation.handle_uninstall(selected) }.each { |line| context.print(line) }
        context[:removed] = true
      end

      step "remove the releases and the launcher", done: ->(context) { context.releases_removed } do |context|
        if Installation.of(context).installed_agents.empty?
          ReleaseRemoval.of(context).call.each { |label, value| context.row(label, value) }
        end
        context[:releases_removed] = true
      end

      outcome :done, offers: "plastic install", because: "Plastic is removed from the chosen agents; the home stays"
    end
  end
end
