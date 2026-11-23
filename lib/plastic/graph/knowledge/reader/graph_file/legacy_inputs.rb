# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Reader
        class GraphFile
          # Turns the `input` of each node of an older graph file into the first row of node_inputs, and takes the field off
          # the node. A node with an empty `input` gives no row.
          class LegacyInputs
            # One node of an older graph file that still has its `input`.
            class Node
              def initialize(node)
                @node = node
              end

              # The first input row of the node, or nil when its `input` is empty; the node loses the field either way.
              def row
                path = @node.delete("input").to_s
                { "intent_id" => @node["intent_id"], "node_id" => @node["id"], "position" => 1, "path" => path } unless path.empty?
              end
            end

            def initialize(data)
              @data = data
            end

            def call
              nodes = Array(@data["nodes"]).grep(Hash).select { |node| node.key?("input") }
              return @data if nodes.empty?

              @data.merge("node_inputs" => Array(@data["node_inputs"]) + nodes.filter_map { |node| Node.new(node).row })
            end
          end
        end
      end
    end
  end
end
