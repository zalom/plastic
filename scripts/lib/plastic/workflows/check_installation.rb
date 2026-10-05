# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "installation_health"

module Plastic
  module Workflows
    # Reports each part of the installation and the repair for each broken
    # one, and fails when a part is broken. It only reads; a repair runs only
    # when the person runs it.
    class CheckInstallation < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :repairs, :managed

      read "check the active release, the launcher, Ruby, the bundle, the hooks and the installer lock" do |context|
        health = InstallationHealth.of(context)
        checks = health.checks
        checks.each { |check| context.row(check.label, check.value) }
        repairs = checks.filter_map(&:repair)
        repairs.each { |repair| context.row("repair:", repair) }
        context[:repairs] = repairs.size
        context[:managed] = health.managed?
      end

      gate "a part of the installation is broken; run the repairs named above, then check again", stops: :failure,
        pass: ->(context) { context.repairs.zero? }

      outcome :unmanaged, if: ->(context) { !context.managed }, offers: "plastic status",
        because: "no release is installed, so only Ruby was checked; install.sh installs a release that plastic version can check"
      outcome :done, offers: "plastic status", because: "the installation is whole, so read the work next"
    end
  end
end
