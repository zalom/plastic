# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../given_file"
require_relative "../../../graph/knowledge/intent/outcome_summary"
require_relative "../../../layout"

module Plastic
  module Workflows
    module Code
      module Intent
        # Writes the file that --from names as the summary of an open intent's outcome, a new revision of outcome.md
        # that keeps its title and every section; refuses a closed intent and a summary that is empty or holds a heading.
        class Outcome < CodeWorkflow
          clear_declarations
          summary "Writes the file that --from names as the summary of the outcome of the intent."

          CLOSED = %w[done abandoned].freeze
          FILE = Layout.name(:outcome)
          SUMMARY = Plastic::Graph::Knowledge::Intent::OutcomeSummary

          sets :intent, :status, :summary_text, :summary_problem, :outcome_reference

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its outcome", stops: :refusal,
            offers: "plastic next", because: "a closed intent keeps its outcome; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

          read "read the summary file" do |context|
            text, problem = GivenFile.text(context.from, "summary")
            context[:summary_text] = text
            context[:summary_problem] = problem || SUMMARY.problem(text)
          end

          gate "%{summary_problem}", stops: :failure,
            words: "the summary file cannot be read, is empty, or holds a heading",
            pass: ->(context) { context.summary_problem.nil? }

          step "write the summary", done: ->(context) { !context.outcome_reference.nil? },
            changes: { knowledge: "outcome.md holds the summary as its new revision", work: "A summarized line in the work log" } do |context|
            body = SUMMARY.for(context.retrieval.fetch(context.intent_id, FILE)&.body).replace(context.summary_text)
            context[:outcome_reference] = context.work.write_document(context.intent_id, FILE, body)
          end

          read "say what was written" do |context|
            context.print("outcome: written from #{context.from}")
          end

          outcome :written, offers: "plastic next", because: "outcome.md holds the summary"
        end
      end
    end
  end
end
