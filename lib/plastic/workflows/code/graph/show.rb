# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../lines"
require_relative "../../run_times"

module Plastic
  module Workflows
    module Code
      module Graph
        # Prints each node, edge and run from the rows. It never reads or writes graph.json.
        class Show < CodeWorkflow
          clear_declarations

          sets :intent

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "print each node" do |context|
            found = found_in(context.retrieval.structure.edges(context.intent_id))
            print_nodes(context, found)
          end

          read "print each need" do |context|
            context.retrieval.structure.edges(context.intent_id).select(&:needs?).each { |edge| context.print("edge: #{edge.from} to #{edge.to}") }
          end

          read "print each run" do |context|
            runs = context.retrieval.structure.runs(context.intent_id)
            runs.each { |run| context.print(Lines.run_line(run)) }
            context.data("runs", runs.map { |run| run_data(run) })
          end

          # A run as data for a JSON answer: its node, number, start, end and length in whole seconds, nil while it runs.
          def self.run_data(run)
            started, ended = run.started_at, run.ended_at
            { "node" => run.node_id, "number" => run.number, "started_at" => Plastic.local(started), "ended_at" => (Plastic.local(ended) if ended), "length_seconds" => (RunTimes.seconds(started, ended) if ended) }
          end

          # Each node's line, then one `input: PATH` line for each of its input paths in the order given.
          def self.print_nodes(context, found)
            intent_id = context.intent_id
            structure = context.retrieval.structure
            paths = structure.node_inputs(intent_id).group_by(&:node_id)
            node_lines(structure.nodes(intent_id), found, paths).each { |line| context.print(line) }
          end

          def self.node_lines(nodes, found, paths) = nodes.flat_map { |node| node_block(node, found, paths) }

          def self.node_block(node, found, paths)
            id = node.id
            [Lines.node(node, found[id]), *input_lines(paths, id)]
          end

          def self.input_lines(paths, node_id) = paths.fetch(node_id, []).map { |row| "input: #{row.path}" }

          # The node each found node was found in, by the found node.
          def self.found_in(edges) = edges.reject(&:needs?).to_h { |edge| [edge.from, edge.to] }

          outcome :done, offers: "plastic graph ready %{intent_id}", because: "the rows hold this graph"
        end
      end
    end
  end
end
