# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "lines"

module Plastic
  module Workflows
    # Prints each node and edge, then overwrites graph.json from rows: the
    # file is never read, so a hand edit never feeds back into the graph.
    class ShowGraph < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :printed_paths

      read "print each node and edge" do |context|
        context.retrieval.nodes(context.intent_id).each { |node| context.print(Lines.node(node)) }
        context.retrieval.edges(context.intent_id).each { |edge| context.print("edge: #{edge.from} to #{edge.to}") }
      end

      step "reprint graph.json", done: ->(context) { !context.printed_paths.nil? } do |context|
        context[:printed_paths] = context.work.print_intent(context.intent_id)
      end

      outcome :done, offers: "plastic graph ready %{intent_id}", because: "graph.json matches the rows"
    end
  end
end
