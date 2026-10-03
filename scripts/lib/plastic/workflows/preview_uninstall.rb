# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation"

module Plastic
  module Workflows
    # On a dry run, lists each file and folder the uninstall would remove,
    # and the home it keeps.
    class PreviewUninstall < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      read "list the files the uninstall would remove" do |context|
        if context.dry_run
          installation = Installation.of(context)
          installation.planned_removals(Installation.selected(context)).each { |path| context.row("remove:", path) }
          context.row("keep:", installation.plastic_home)
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic uninstall",
        because: "the preview changed no file"
      outcome :continue, offers: "plastic uninstall", because: "remove Plastic from the chosen agents"
    end
  end
end
