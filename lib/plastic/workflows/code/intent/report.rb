# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/intent/reporter"

module Plastic
  module Workflows
    module Code
      module Intent
        # Records a report of an intent. A path recorded before is left as it is. Which work needs a report is the guidance
        # of PLASTIC.md; the command records.
        class Report < CodeWorkflow
          clear_declarations

          CLOSED = %w[done abandoned].freeze
          MANDATORY = Plastic::Graph::Knowledge::Intent::Reporter::MANDATORY

          sets :intent, :status, :problem, :recorded, :reference

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its outcome", stops: :failure,
            offers: "plastic next", because: "a closed intent keeps its outcome; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

          read "check the report" do |context|
            context[:problem] = context.work.report_problem(context.intent, context.path, context.settings.selection)
          end

          gate "%{problem}", stops: :failure,
            words: "the path is no plain path to a text file of a read type in resources/output/reports/",
            pass: ->(context) { context.problem.nil? }

          read "find an earlier record" do |context|
            context[:recorded] = context.work.reported?(context.intent_id, context.path)
          end

          step "record the report", done: ->(context) { context.recorded || !context.reference.nil? },
            changes: { knowledge: "The report is recorded, read into the rows and listed under Reports in the outcome" } do |context|
            context[:reference] = context.work.report_intent(context.intent, context.path, Report.text(context))
          end

          read "say what was recorded" do |context|
            context.print("reported: #{context.path}")
          end

          outcome :done, offers: "plastic next", because: "the outcome lists the report and the sync reads it"

          # The text of the log line: MANDATORY for a path the setting reports.mandatory names, else none.
          def self.text(context) = context.settings.selection.reports.mandatory?(context.path) ? MANDATORY : ""
        end
      end
    end
  end
end
