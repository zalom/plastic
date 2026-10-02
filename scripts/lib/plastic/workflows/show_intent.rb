# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/spec"
require_relative "lines"

module Plastic
  module Workflows
    # Prints one intent's status, criteria count, open decisions, rulings,
    # nodes and last savepoint lines; refuses an unknown id.
    class ShowIntent < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "print the intent" do |context|
        context.print("intent: #{context.intent.heading}")
        print_spec(context)
        print_rulings(context)
        print_nodes(context)
        print_savepoints(context)
      end

      def self.print_spec(context)
        spec = Graph::Spec.new(context.retrieval, context.intent_id)
        context.print("criteria: #{spec.done_criteria.size}")
        spec.open_decisions.each { |decision| context.print("open decision: #{decision}") }
      end

      def self.print_rulings(context)
        Lines.rulings(context.retrieval.rulings(context.intent_id)).each { |line| context.print(line) }
      end

      def self.print_nodes(context)
        context.retrieval.nodes(context.intent_id).each { |node| context.print(Lines.node(node)) }
      end

      def self.print_savepoints(context)
        context.retrieval.savepoints(context.intent_id).last(3).each { |savepoint| context.print("savepoint: #{savepoint.line}") }
      end

      outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} is shown"
    end
  end
end
