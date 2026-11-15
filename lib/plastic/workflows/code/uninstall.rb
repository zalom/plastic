# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../installations"
require_relative "../installation"
require_relative "../release_removal"

module Plastic
  module Workflows
    module Code
      # Removes what the record of each picked harness lists, then the
      # releases and the launcher once no harness stays installed. The home
      # with its stores stays.
      class Uninstall < CodeWorkflow
        [facts, steps, outcomes].each(&:clear)

        UNRECORDED = "%s: no record lists what Plastic wrote; run plastic install --reinstall to write it, then run this again"

        sets :removed, :releases_removed, :unrecorded, :released

        step "remove what each record lists", done: ->(context) { context.removed } do |context|
          plastic_home = context.scope.plastic_home
          unrecorded = context.picked.reject do |name|
            removed = Installations.remove(plastic_home, name)
            removed&.each { |label, path| context.row(label, path) }
          end
          unrecorded.each { |name| context.print(format(UNRECORDED, name)) }
          context[:unrecorded] = unrecorded
          context[:removed] = true
        end

        step "remove the releases and the launcher", done: ->(context) { context.releases_removed } do |context|
          rows = Installation.of(context).kept([]).empty? ? ReleaseRemoval.of(context).call.to_a : []
          rows.each { |label, value| context.row(label, value) }
          context[:released] = rows.any?
          context[:releases_removed] = true
        end

        outcome :released, if: ->(context) { context.released }, offers: nil,
          because: "Plastic is removed from %{harnesses}, launcher included; install.sh installs it again, and the home stays"
        outcome :unrecorded, if: ->(context) { !context.picked.empty? && context.unrecorded == context.picked },
          offers: "plastic install --reinstall", because: "no record lists what Plastic wrote for %{harnesses}, so nothing was removed"
        outcome :done, offers: "plastic init", because: "Plastic is removed from %{harnesses}; the home stays"
      end
    end
  end
end
