# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation_health"

module Plastic
  module Workflows
    # Reports each part of the installation and the repair for each broken
    # one. It only reads; a repair runs only when the person runs it.
    class CheckInstallation < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :repairs

      read "check the active release, the launcher, Ruby, the bundle, the hooks and the installer lock" do |context|
        checks = InstallationHealth.of(context).checks
        checks.each { |check| context.row(check.label, check.value) }
        repairs = checks.filter_map(&:repair)
        repairs.each { |repair| context.print("repair: #{repair}") }
        context[:repairs] = repairs.size
      end

      outcome :damaged, if: ->(context) { context.repairs.positive? }, offers: "plastic version",
        because: "a part of the installation is broken; run the repairs named above, then check again"
      outcome :done, offers: "plastic status", because: "the installation is whole, so read the work next"
    end
  end
end
