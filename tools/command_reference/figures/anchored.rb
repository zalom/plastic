# frozen_string_literal: true

require "forwardable"

module CommandReference
  module Figures
    # A place that words end at or center on.
    Anchored = Data.define(:point, :side) do
      extend Forwardable

      def_delegators :point, :left, :top
    end
  end
end
