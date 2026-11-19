# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/intent/reporter"

module Plastic
  module Workflows
    module Code
      module Intent
        # Records a report the owner asked for, or one the setting reports.mandatory names. A path recorded before is
        # left as it is.
        class Report < CodeWorkflow
          clear_declarations

          CLOSED = %w[done abandoned].freeze
          MANDATORY = Plastic::Graph::Knowledge::Intent::Reporter::MANDATORY
          REFUSED = "no owner message of this store or session holds the words of --asked, and reports.mandatory does not name %{path}; Plastic records only a report the owner asked for"

          sets :intent, :status, :problem, :recorded, :given, :reference

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its outcome", stops: :failure,
            offers: "plastic next", because: "a closed intent keeps its outcome; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

          read "check the report" do |context|
            context[:problem] = context.work.report_problem(context.intent, context.path)
          end

          gate "%{problem}", stops: :failure,
            words: "the path is outside resources/output/reports/ or names no file",
            pass: ->(context) { context.problem.nil? }

          read "find the owner's words" do |context|
            context[:recorded] = context.work.reported?(context.intent_id, context.path)
            context[:given] = Report.given(context)
          end

          gate REFUSED, stops: :refusal, offers: "plastic next", because: "a report needs the owner's words, or the setting reports.mandatory",
            pass: ->(context) { context.recorded || !context.given.nil? }

          step "record the report", done: ->(context) { context.recorded || !context.reference.nil? },
            changes: { knowledge: "The report is recorded, read into the rows and listed under Reports in the outcome" } do |context|
            context[:reference] = context.work.report_intent(context.intent, context.path, context.given)
          end

          read "say what was recorded" do |context|
            context.print("reported: #{context.path}")
          end

          outcome :done, offers: "plastic next", because: "the outcome lists the report and the sync reads it"

          # MANDATORY for a path the setting names, the owner's words when an owner message holds them, else nil.
          def self.given(context)
            return MANDATORY if context.settings.selection.reports.mandatory?(context.path)

            context.asked if context.work.asked?(context.asked)
          end
        end
      end
    end
  end
end
