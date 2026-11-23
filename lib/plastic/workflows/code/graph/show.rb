# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../lines"

module Plastic
  module Workflows
    module Code
      module Graph
        # Prints each node and edge from the rows. It never reads or writes graph.json.
        class Show < CodeWorkflow
          clear_declarations

          sets :intent

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "print each node and edge" do |context|
            edges = context.retrieval.structure.edges(context.intent_id)
            found = edges.select { |edge| edge.kind == "found_in" }.to_h { |edge| [edge.from, edge.to] }
            context.retrieval.structure.nodes(context.intent_id).each { |node| context.print(Lines.node(node, found[node.id])) }
            edges.select { |edge| edge.kind == "needs" }.each { |edge| context.print("edge: #{edge.from} to #{edge.to}") }
          end

          outcome :done, offers: "plastic graph ready %{intent_id}", because: "the rows hold this graph"
        end
      end
    end
  end
end
