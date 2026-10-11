# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../installations"
require_relative "installation"
require_relative "release_removal"

module Plastic
  module Workflows
    # Removes what the record of each picked harness lists, then the
    # releases and the launcher once no harness stays installed. The home
    # with its stores stays.
    class UninstallPlastic < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      UNRECORDED = "%s: no record lists what Plastic wrote; run plastic install --reinstall to write it, then run this again"

      sets :removed, :releases_removed

      step "remove what each record lists", done: ->(context) { context.removed } do |context|
        plastic_home = context.scope.plastic_home
        context.picked.each do |name|
          removed = Installations.remove(plastic_home, name)
          removed ? removed.each { |path| context.row("removed:", path) } : context.print(format(UNRECORDED, name))
        end
        context[:removed] = true
      end

      step "remove the releases and the launcher", done: ->(context) { context.releases_removed } do |context|
        if Installation.of(context).kept([]).empty?
          ReleaseRemoval.of(context).call.each { |label, value| context.row(label, value) }
        end
        context[:releases_removed] = true
      end

      outcome :done, offers: "plastic init", because: "Plastic is removed from %{harnesses}; the home stays"
    end
  end
end
