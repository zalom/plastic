# frozen_string_literal: true

module Plastic
  class Routine < CLI::Command
    # The block form of `workflow`: one `on` line per outcome, each an edge
    # of the chain.
    class Branches
      def initialize(chain, key)
        @chain = chain
        @key = key
      end

      def on(outcome, **edge) = @chain.edge(@key, outcome, edge.fetch(:next))
    end
  end
end
