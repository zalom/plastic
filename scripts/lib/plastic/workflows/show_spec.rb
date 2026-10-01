# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/spec"

module Plastic
  module Workflows
    # Prints the grilling method, then the intent's open decisions.
    class ShowSpec < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      GRILLING = File.expand_path("../../../../docs/grilling.md", __dir__)

      sets :decisions

      read "print the grilling method" do |context|
        context.print(File.read(GRILLING))
      end

      read "read the open decisions" do |context|
        context[:decisions] = Graph::Spec.new(context.retrieval, context.intent_id).open_decisions
        context.decisions.each { |decision| context.print("open: #{decision}") }
      end

      outcome :open, if: ->(context) { context.decisions.any? }, offers: "plastic intent rule %{intent_id} TEXT",
        because: "an open decision is still unrecorded"
      outcome :done, offers: "plastic auto start %{intent_id}", because: "the spec carries no open decision"
    end
  end
end
