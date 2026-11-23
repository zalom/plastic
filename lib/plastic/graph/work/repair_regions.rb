# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The regions to re-plan after a stop: each node that failed or waits on the owner, with the
      # nodes that depend on it through needs edges, transitively, left out when they are done or removed.
      class RepairRegions
        # A node as the answer shows it: its id, title and state.
        Row = Data.define(:id, :title, :state) do
          def stopped? = %w[failed needs_info impeded].include?(state)

          def finished? = %w[done removed].include?(state)

          def to_answer = to_h.transform_keys(&:to_s)
        end

        def initialize(nodes, edges)
          @rows = nodes.map { |node| Row.new(**node.to_h.slice(:id, :title, :state)) }
          @waiting = edges.select { |edge| edge.kind == "needs" }.group_by(&:from).transform_values { |list| list.map(&:to) }
        end

        # One hash for each stopped node: its id, title and state, and the nodes downstream of it.
        def to_a
          @rows.select(&:stopped?).map { |row| row.to_answer.merge("downstream" => downstream(row.id)) }
        end

        private

        def downstream(root)
          reached = reach(root)
          @rows.select { |row| reached.include?(row.id) && !row.finished? }.map(&:to_answer)
        end

        def reach(root, seen = [])
          @waiting.fetch(root, []).each { |id| reach(id, seen << id) unless seen.include?(id) }
          seen
        end
      end
    end
  end
end
