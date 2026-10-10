# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A dashed frame around a group of cards.
    class Zone < Data.define(:left, :top, :width, :height, :name)
      include Anchored

      def title_bounds
        edge = left + 14
        [edge, top + 8, edge + (name.size * 6.5), top + 24]
      end

      def markup(_id) = %(<rect class="zone" x="#{left}" y="#{top}" width="#{width}" height="#{height}" rx="12"/>) + Shapes.text([left + 14, top + 20], "s", name)
    end
  end
end
