# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../doctor"
require_relative "installation"

module Plastic
  module Workflows
    # Runs the checks of the shared parts and of one harness, prints a row for
    # each, and names each repair once. It reads files and changes none.
    class CheckHealth < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :repairs

      read "check the installation, the databases, the hooks and the instruction files of the harness" do |context|
        checks = CheckHealth.checks(context)
        checks.each { |check| context.row(check.label, check.value) }
        repairs = checks.filter_map(&:repair).uniq
        context.row("repair:", repairs) unless repairs.empty?
        context[:repairs] = repairs.size
      end

      gate "a check found a problem; run the repairs named above, then run plastic doctor again", stops: :failure,
        pass: ->(context) { context.repairs.zero? }

      outcome :done, offers: "plastic status", because: "every check passed, so read the work next"

      def self.checks(context)
        scope = context.scope
        Doctor.checks(scope, Doctor.kind(context.harness_name || Doctor.harness(scope)), running: running(context))
      end

      def self.running(context) = Installation.source(Installation.package_root(context.scope)) && Installation.of(context).version
    end
  end
end
