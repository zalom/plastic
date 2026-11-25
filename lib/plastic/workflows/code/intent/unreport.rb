# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/intent/report_file"

module Plastic
  module Workflows
    module Code
      module Intent
        # Removes a report of an intent that was recorded by mistake. Only a report whose record still counts is removed,
        # and a move to resources/tmp/ never writes over a file there.
        class Unreport < CodeWorkflow
          clear_declarations

          sets :intent, :problem, :removed

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "check the record" do |context|
            context[:problem] = context.work.unreport_problem(Unreport.of(context), context.to_tmp)
          end

          gate "%{problem}", stops: :failure,
            words: "the path is no recorded report of the intent, or a file already holds its place in resources/tmp/",
            pass: ->(context) { context.problem.nil? }

          step "remove the report", done: ->(context) { !context.removed.nil? },
            changes: { knowledge: "The rows of the report are dropped, its line leaves the Reports list of the outcome, and its file is deleted or moved to resources/tmp/",
                       work: "A removed line with the reason follows the reported line, and a closed intent gets an amended line" } do |context|
            context[:removed] = context.work.unreport_intent(Unreport.of(context), context.reason, to_tmp: context.to_tmp)
          end

          read "say what was removed" do |context|
            context.print(context.removed.words)
          end

          outcome :done, offers: "plastic next", because: "the report is no longer recorded, and the sync no longer reads it"

          # The file of the report the command names.
          def self.of(context) = Plastic::Graph::Knowledge::Intent::ReportFile.new(context.intent, context.path)
        end
      end
    end
  end
end
