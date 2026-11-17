# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../doctor"
require_relative "../../doctor/search_index"
require_relative "../installation"

module Plastic
  module Workflows
    module Code
      # Runs the checks of the shared parts and of one harness, prints a row for
      # each, and names each repair once. It rebuilds the search rows of a store
      # that are out of step, adds the work log lines a failed write left out, and changes nothing else.
      class Doctor < CodeWorkflow
        clear_declarations

        sets :repairs

        read "check the installation, the databases, the hooks and the instruction files of the harness" do |context|
          checks = Plastic::Doctor.check(context.scope, harness: context.harness_name || Plastic::Doctor.harness(context.scope, session: context.session),
            running: Installation.running(context.scope), now: context.now, store: context.settings.store)
          checks.each { |check| context.row(check.label, check.value) }
          repairs = checks.filter_map(&:repair).uniq
          context.row("repair:", repairs) unless repairs.empty?
          context[:repairs] = repairs.size
        end

        read "check the search index of each store and rebuild it when its rows are out of step" do |context|
          checks = Plastic::Doctor::SearchIndex.checks(context.scope)
          checks.each { |check| context.row(check.label, check.value) }
          repairs = checks.filter_map(&:repair).uniq
          context.row("repair:", [*repairs]) unless repairs.empty?
          context[:repairs] = context.repairs + repairs.size
        end

        gate "a check found a problem; run the repairs named above, then run plastic doctor again", stops: :failure,
          pass: ->(context) { context.repairs.zero? }

        outcome :done, offers: "plastic status", because: "every check passed, so read the work next"
      end
    end
  end
end
