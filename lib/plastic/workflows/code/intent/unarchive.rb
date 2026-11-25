# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Intent
        # Restores the archived directory snapshot, including bytes and metadata.
        class Unarchive < CodeWorkflow
          clear_declarations

          sets :problem, :kind, :ok

          forget_stop :problem, :kind, :ok

          step "restore the intent", done: ->(context) { !context.ok.nil? || !context.problem.nil? },
            changes: { work: "The intent leaves the archive", knowledge: "The files kept for the intent are restored" } do |context|
            ok, problem, kind = context.work.unarchive_intent(context.intent_id)
            context[:ok] = ok
            context[:problem] = problem
            context[:kind] = kind
          end

          gate "%{problem}", stops: :failure,
            words: "a file of the intent cannot be restored",
            pass: ->(context) { context.kind != :failure }
          gate "%{problem}", stops: :refusal,
            words: "the intent is not archived, or its snapshot is on the first home",
            pass: ->(context) { context.problem.nil? }

          read "say it was restored" do |context|
            context.print("intent: #{context.intent_id} unarchived")
          end

          outcome :done, offers: "plastic intent show %{intent_id}", because: "intent %{intent_id} is back on the checkout"
        end
      end
    end
  end
end
