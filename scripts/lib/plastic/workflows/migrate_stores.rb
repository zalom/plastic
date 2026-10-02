# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Imports every legacy store under the home into rows: `Sync::LegacyImport`
    # for the intent files, then the rulings, links, roadmaps and originals
    # that import does not do on its own, and the archive of a done or
    # abandoned intent once its rows are in.
    class MigrateStores < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :reports, :problem

      step "migrate every legacy store", done: ->(context) { !context.reports.nil? } do |context|
        context[:reports] = context.work.migrate_stores(context.apply ? :apply : :dry_run)
        context[:problem] = problem_lines(context.reports)
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? || !context.apply }

      read "say what each store holds" do |context|
        context.reports.each { |report| context.print(report_line(report)) }
        context.print(totals_line(context.reports))
      end

      outcome :done, offers: "plastic next", because: "the stores import as rows"

      def self.problem_lines(reports)
        lines = reports.reject { |report| report.problems.empty? }.flat_map(&:problems)
        lines.empty? ? nil : lines.join("\n")
      end

      def self.report_line(report)
        return "#{report.store}: skipped, already imported" if report.skipped
        return "#{report.store}: #{report.problems.join("; ")}" if report.problems.any?

        "#{report.store}: #{Graph::Schema.phrase(report.counts)}"
      end

      def self.totals_line(reports)
        totals = reports.reject(&:skipped).each_with_object(Hash.new(0)) do |report, sums|
          report.counts.each { |key, value| sums[key] += value }
        end
        "total: #{Graph::Schema.phrase(totals)}"
      end
    end
  end
end
