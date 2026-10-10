# frozen_string_literal: true

require "cgi/escape"
require_relative "canvas"

module ArchitectureFigures
  # Part of the figure builder; see docs/contributing/ARCHITECTURE.md.
  module Shapes
    def self.text(at, style, content)
      left, top, anchor = at
      tail = anchor ? %( text-anchor="#{anchor}") : ""
      %(<text class="#{style}" x="#{left}" y="#{top}"#{tail}>#{CGI.escapeHTML(content)}</text>)
    end

    # A shape with a rectangle that arrows can start and end on.
    module Anchored
      def right = left + width

      def bottom = top + height

      def anchor(side, fraction = 0.5)
        across = left + (fraction * width)
        down = top + (fraction * height)
        { left: [left, down], right: [right, down], top: [across, top], bottom: [across, bottom] }.fetch(side)
      end
    end
  end
end
require_relative "shapes/label"
require_relative "shapes/box"
require_relative "shapes/cylinder"
require_relative "shapes/zone"
require_relative "shapes/arrow"
require_relative "shapes/key"
require_relative "shapes/mark"
require_relative "shapes/matrix_row"
require_relative "shapes/matrix"
require_relative "shapes/terminal"
