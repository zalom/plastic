# frozen_string_literal: true

require_relative "text"

module ArchitectureFigures
  module Shapes
    # One line of text.
    class Label < Data.define(:left, :top, :text, :style)
      def markup(_id) = Shapes.text([left, top], style, text)
    end
  end
end
