# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Takes a done, abandoned or future intent off the checkout. Its rows stay.
    class ArchiveIntent < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :kind, :ok

      forget_stop :problem, :kind, :ok

      step "archive the intent", done: ->(context) { !context.ok.nil? || !context.problem.nil? } do |context|
        ok, problem, kind = context.work.archive_intent(context.intent_id)
        context[:ok] = ok
        context[:problem] = problem
        context[:kind] = kind
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.kind != :failure }
      gate "%{problem}", stops: :refusal, pass: ->(context) { context.kind != :refusal }

      read "say it was archived" do |context|
        context.print("intent: #{context.intent_id} archived")
      end

      outcome :done, offers: "plastic status", because: "intent %{intent_id} is off the checkout"
    end
  end
end
