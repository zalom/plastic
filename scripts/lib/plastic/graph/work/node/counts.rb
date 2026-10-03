# frozen_string_literal: true

require_relative "../node"

module Plastic
  module Graph
    module Work
      class Node
        # One intent's node counts by state, rendered as a status line.
        class Counts
          def initialize(nodes) = @nodes = nodes

          def line
            return "no nodes" if counts.empty?

            counts.map { |state, count| "#{state}: #{count}" }.join(", ")
          end

          private

          def counts = @nodes.group_by(&:state).transform_values(&:size)
        end
      end
    end
  end
end
