# frozen_string_literal: true

module Plastic
  class CLI
    # The command a stopped call offers as next:, and the rule behind it.
    Offer = Data.define(:command, :because) do
      def self.none(because) = new(nil, because)

      def apply(output) = command ? output.next_step(command, because:) : output
    end
  end
end
