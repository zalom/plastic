# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Writes one ruling; fails when --supersedes names no such ruling.
    class AddRuling < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :id

      step "write the ruling", done: ->(context) { !context.problem.nil? || !context.id.nil? } do |context|
        ruling = context.work.add_ruling(intent_id: context.intent_id, text: context.text, supersedes: context.supersedes)
        context[:id] = ruling&.id
        context[:problem] = ruling ? nil : "no ruling #{context.supersedes} in intent #{context.intent_id}"
      end

      gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

      read "say what was written" do |context|
        context.print("ruling: #{context.id}")
      end

      outcome :done, offers: "plastic intent brief %{intent_id}", because: "ruling %{id} is on record"
    end
  end
end
