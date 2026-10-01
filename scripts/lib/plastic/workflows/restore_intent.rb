# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Prints an archived intent's folder back from its rows, byte for byte.
    class RestoreIntent < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :ok

      step "restore the intent", done: ->(context) { !context.ok.nil? || !context.problem.nil? } do |context|
        ok, problem, = context.work.restore_intent(context.intent_id)
        context[:ok] = ok
        context[:problem] = problem
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "say it was restored" do |context|
        context.print("intent: #{context.intent_id} restored")
      end

      outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} is back on the checkout"
    end
  end
end
