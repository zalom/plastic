# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../installations"
require_relative "installation"
require_relative "release_removal"

module Plastic
  module Workflows
    # On a dry run, lists what the record of each picked harness names, the
    # releases and the launcher among them when no harness stays installed,
    # and the home it keeps.
    class PreviewUninstall < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      read "list what the uninstall would remove or change" do |context|
        if context.dry_run
          plastic_home = context.scope.plastic_home
          Installations.planned(plastic_home, context.picked).each { |label, path| context.row(label, path) }
          releases = Installation.of(context).kept(context.picked).empty? ? ReleaseRemoval.of(context).planned : []
          releases.each { |path| context.row("remove:", path) }
          context.row("keep:", plastic_home)
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
        because: "the preview changed no file"
      outcome :continue, offers: "plastic uninstall %{answer}", because: "remove Plastic from %{harnesses}"
    end
  end
end
