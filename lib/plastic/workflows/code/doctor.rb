# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../../doctor"
require_relative "../../doctor/search_index"
require_relative "../../doctor/folder_layout"
require_relative "../installation"

module Plastic
  module Workflows
    module Code
      # Runs the checks of the shared parts and of one harness, prints a row for
      # each, and names each repair once. It rebuilds the search rows of a store
      # that are out of step, adds the work log lines a failed write left out, and changes nothing else. A folder that
      # breaks the layout makes plastic intent repair the next step.
      class Doctor < CodeWorkflow
        clear_declarations

        FAILED = "a check found a problem; run the repairs named above, then run plastic doctor again"

        sets :repairs, :layout_repair

        # Prints a row for each check and one repair row that names each repair once, adds the repairs to :repairs, and
        # gives them back.
        def self.report(context, checks)
          checks.each { |check| context.row(check.label, check.value) }
          repairs = checks.filter_map(&:repair).uniq
          context.row("repair:", repairs) unless repairs.empty?
          context[:repairs] = context.repairs.to_i + repairs.size
          repairs
        end

        read "check the installation, the databases, the hooks and the instruction files of the harness" do |context|
          report(context, Plastic::Doctor.check(context.scope, harness: context.harness_name || Plastic::Doctor.harness(context.scope, session: context.session),
            running: Installation.running(context.scope), now: context.now, store: context.settings.store))
        end

        read "check the search index of each store and rebuild it when its rows are out of step" do |context|
          report(context, Plastic::Doctor::SearchIndex.checks(context.scope))
        end

        read "check that the folders of each store follow the layout" do |context|
          repairs = report(context, Plastic::Doctor::FolderLayout.checks(context.scope, reports: context.settings.selection.reports))
          context[:layout_repair] = repairs.find { |repair| repair.start_with?(Plastic::Doctor::FolderLayout::COMMAND) }
        end

        # A folder that breaks the layout names its repair as the next step; the other findings name theirs above.
        gate FAILED, stops: :failure, offers: "%{layout_repair}", pass: ->(context) { context.repairs.zero? || context.layout_repair.nil? }
        gate FAILED, stops: :failure, pass: ->(context) { context.repairs.zero? }

        outcome :done, offers: "plastic status", because: "every check passed, so read the work next"
      end
    end
  end
end
