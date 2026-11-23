# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/intent/reporter"

module Plastic
  module Workflows
    module Code
      module Intent
        # Records a report of an intent. A path recorded before is recorded again only when its sha256 changed. Which work needs a report is the guidance
        # of PLASTIC.md; the command records.
        class Report < CodeWorkflow
          clear_declarations

          CLOSED = %w[done abandoned].freeze
          MANDATORY = Plastic::Graph::Knowledge::Intent::Reporter::MANDATORY

          sets :intent, :status, :problem, :state, :reference, :restated

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its outcome", stops: :refusal,
            offers: "plastic next", because: "a closed intent keeps its outcome; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

          read "check the report" do |context|
            context[:problem] = context.work.report_problem(Report.of(context), context.settings.selection)
          end

          gate "%{problem}", stops: :failure,
            words: "the path is no plain path to a text file of a read type in resources/output/reports/",
            pass: ->(context) { context.problem.nil? }

          read "find an earlier record" do |context|
            context[:state] = context.work.report_state(Report.of(context))
          end

          step "record the report", done: ->(context) { !context.reference.nil? || !context.restated.nil? },
            changes: { knowledge: "A new or changed report is recorded, read into the rows and listed under Reports in the outcome; an unchanged one only has its Reports line rewritten when the setting changed its form" } do |context|
            Report.record(context)
          end

          read "say what was recorded" do |context|
            context.print(context.restated ? Report.restated_words(context.path) : Report.words(context.state, context.path))
          end

          outcome :done, offers: "plastic next", because: "the outcome lists the report and the sync reads it"

          # The file of the report the command names.
          def self.of(context) = Plastic::Graph::Knowledge::Intent::ReportFile.new(context.intent, context.path)

          # A new or changed report is recorded in full; an unchanged one only has its outcome line rewritten, no row and no log line.
          def self.record(context)
            (context.state.kind == :unchanged) ? restate(context) : write(context)
          end

          def self.restate(context) = (context[:restated] = context.work.restate_report(of(context), text(context)))

          def self.write(context) = (context[:reference] = context.work.report_intent(of(context), text(context)))

          # What the command says: a first record, a record again of a changed file, or that nothing was written.
          def self.words(state, path)
            case state.kind
            when :unchanged then "unchanged: #{path} is already recorded with this sha256; nothing written"
            when :changed then "reported again: #{path} (sha256 #{state.sha256})"
            else "reported: #{path}"
            end
          end

          # What the command says when only the outcome line of an unchanged report was rewritten.
          def self.restated_words(path) = "unchanged: #{path} is already recorded with this sha256; outcome line rewritten, no row and no log line"

          # The text of the log line: MANDATORY for a path the setting reports.mandatory names, else none.
          def self.text(context) = context.settings.selection.reports.mandatory?(context.path) ? MANDATORY : ""
        end
      end
    end
  end
end
