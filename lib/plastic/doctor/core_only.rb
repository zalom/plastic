# frozen_string_literal: true

module Plastic
  module Doctor
    # The doctor of a harness that declares none: the core checks hold for it, and it adds no check of its own.
    class CoreOnly
      def initialize(scope, running:)
        @scope = scope
        @running = running
      end

      def checks = []
    end
  end
end
