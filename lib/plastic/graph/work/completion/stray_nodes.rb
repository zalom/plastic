# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      module Completion
        # The done nodes whose criterion key the spec does not have, as one list.
        module StrayNodes
          HEADER = "These done nodes have no criterion key, or a key spec.md lacks:"

          def self.message(nodes, keys)
            strays = nodes.reject { |node| keys.include?(node.criterion) }
            [HEADER, *strays.map(&:bullet)].join("\n") unless strays.empty?
          end
        end
      end
    end
  end
end
