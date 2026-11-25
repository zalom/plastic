# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The done and in-progress lines of one intent's nodes.
      class NodeLines
        IN_PROGRESS = %w[claimed needs_info impeded failed].freeze

        def initialize(nodes)
          @nodes = nodes
        end

        def rows = [*done, *in_progress]

        private

        def done = fields(%w[done], :id, :title).map { |id, title| ["done:", "#{id} #{title}"] }

        def in_progress = fields(IN_PROGRESS, :id, :state, :title).map { |id, state, title| ["in progress:", "#{id} #{state} #{title}"] }

        def fields(states, *names) = names.map { |name| of_state(states).map(&name) }.transpose

        def of_state(states) = @nodes.select { |node| states.include?(node.state) }
      end
    end
  end
end
