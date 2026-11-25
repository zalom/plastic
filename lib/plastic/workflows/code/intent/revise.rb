# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Rewrites an intent's What and Why; a done or abandoned intent refuses,
        # and a dry run prints the change and writes nothing.
        class Revise < CodeWorkflow
          clear_declarations

          CLOSED = %w[done abandoned].freeze

          sets :intent, :status, :change, :problem, :reference

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          gate "intent %{intent_id} is %{status}; a closed intent keeps its What and Why", stops: :refusal,
            offers: "plastic next", because: "a closed intent keeps its What and Why; pick other work",
            pass: ->(context) { !CLOSED.include?(context.status) }

          read "check the change" do |context|
            context[:change] = context.work.revision(context.intent, context.line, context.why)
            context[:problem] = context.change ? context.change.problem : "intent #{context.intent_id} has no file row; run plastic store sync up first"
          end

          gate "%{problem}", stops: :failure,
            words: "the intent has no file row, the new What holds a line break, or the What and Why read as before",
            pass: ->(context) { context.problem.nil? }

          read "show the change" do |context|
            change = context.change
            context.print("what was: #{change.intent.title}")
            context.print("what: #{change.line}")
            show_why(context, change) if change.why
          end

          step "write the revision", done: ->(context) { context.dry_run || !context.reference.nil? },
            changes: { knowledge: "The intent file holds the new What and Why", work: "The title is updated and the work log line keeps the old What and Why" } do |context|
            context[:reference] = context.work.revise_intent(context.change)
          end

          read "say what was written" do |context|
            context.print("revision: #{context.reference}") unless context.dry_run
          end

          outcome :previewed, if: ->(context) { context.dry_run }, offers: "%{original_command}",
            because: "the dry run wrote nothing"
          outcome :done, offers: nil, because: "the rows and the files hold the new What and Why"

          def self.show_why(context, change)
            context.print("why was: #{change.old_why}")
            context.print("why: #{change.why}")
          end
        end
      end
    end
  end
end
