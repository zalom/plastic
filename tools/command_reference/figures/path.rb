# frozen_string_literal: true

module CommandReference
  module Figures
    # A line through points, ending in an arrow.
    Path = Data.define(:points, :css) do
      def bottom = points.map(&:top).max

      def markup = %(<path d="M #{points.join(" L ")}" class="#{css}"/>\n#{Head.new(points.last, points[-2]).markup})
    end
  end
end
