# frozen_string_literal: true

module CommandReference
  module Dsl
    # Wraps a statement longer than a width after a top-level comma, and cuts what still does not fit.
    class Layout
      def initialize(width)
        @width = width
      end

      def rows(code_rows) = code_rows.flat_map { |row| row.spread(self) }

      def lines(text) = (text.size <= @width) ? [text] : Wrapper.new(text, @width).lines
    end
  end
end
