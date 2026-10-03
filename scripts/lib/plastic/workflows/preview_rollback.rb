# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "release_update"

module Plastic
  module Workflows
    # Reads the activated releases and picks the one to switch to: the named
    # version, or the previous release. A dry run names the switch.
    class PreviewRollback < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :active, :to, :releases

      read "read the activated releases" do |context|
        activation = ReleaseUpdate.of(context).activation
        context[:active] = activation.active_version
        context[:to] = context.target || activation.previous_version
        context[:releases] = activation.versions
      end

      gate "no release is installed under this home; install one with install.sh first", stops: :refusal,
        pass: ->(context) { context.active }
      gate "%{target} is not installed", stops: :refusal,
        pass: ->(context) { context.target.nil? || context.releases.include?(context.target) }
      gate "no previous release to go back to", stops: :refusal, pass: ->(context) { context.to }

      read "say what the rollback would do" do |context|
        if context.dry_run
          context.row("active:", context.active)
          context.row("to:", context.to)
          context.row("releases:", context.releases.join(", "))
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic rollback", because: "the preview changed no file"
      outcome :continue, offers: "plastic rollback", because: "switch the active release"
    end
  end
end
