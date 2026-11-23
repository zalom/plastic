# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The regions to re-plan after a stop: each node that failed or waits on the owner, with the
      # nodes that depend on it through needs edges, transitively, left out when they are done or removed.
      class RepairRegions
        STOPPED = %w[failed needs_info impeded].freeze
        FINISHED = %w[done removed].freeze

        def initialize(nodes, edges)
          @nodes = nodes
          @waiting = edges.select { |edge| edge.kind == "needs" }.group_by(&:from).transform_values { |list| list.map(&:to) }
        end

        # One hash for each stopped node: its id, title and state, and the nodes downstream of it.
        def to_a
          @nodes.select { |node| STOPPED.include?(node.state) }.map { |node| region(node) }
        end

        private

        def region(node)
          { "id" => node.id, "title" => node.title, "state" => node.state, "downstream" => downstream(node.id) }
        end

        def downstream(root)
          reached = reach(root)
          @nodes.select { |node| reached.include?(node.id) && !FINISHED.include?(node.state) }.map { |node| node.to_h.slice(:id, :title, :state).transform_keys(&:to_s) }
        end

        def reach(root, seen = [])
          @waiting.fetch(root, []).each { |id| reach(id, seen << id) unless seen.include?(id) }
          seen
        end
      end
    end
  end
end
