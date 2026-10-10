# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"
require_relative "go_ahead"
require_relative "lines"

module Plastic
  module Workflows
    # Prints the grilling method, then the intent's open decisions; refuses
    # an unknown id.
    class ShowSpec < CodeWorkflow
      extend GoAhead

      [facts, steps, outcomes].each(&:clear)

      GRILLING = File.expand_path("../../../../docs/grilling.md", __dir__)

      sets :intent, :decisions, :criteria, :why, :handoff_text

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "print the grilling method" do |context|
        context.print(File.read(GRILLING))
        context.print("spec: #{Lines::CRITERIA}")
      end

      read "read the open decisions" do |context|
        spec = Graph::Knowledge::Spec.new(context.retrieval, context.intent_id)
        context[:decisions] = spec.open_decisions
        context[:criteria] = spec.done_criteria
        context.decisions.each { |decision| context.print("open: #{decision}") }
      end

      reads_go_ahead

      outcome :open, if: ->(context) { context.decisions.any? }, offers: "plastic intent rule %{intent_id} TEXT",
        because: "an open decision is still unrecorded"
      outcome :no_criterion, if: ->(context) { context.criteria.empty? }, offers: "plastic sync up",
        because: "the spec names no done criterion; write them in spec.md first"
      outcome :agent_needed, if: ->(context) { !context.handoff_text.nil? }
      outcome :done, offers: "plastic auto %{intent_id}", because: "the spec carries no open decision"
    end
  end
end
