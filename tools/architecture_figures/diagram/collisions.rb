# frozen_string_literal: true

module ArchitectureFigures
  class Diagram
    # The places where an arrow or its note runs through a card or the title of a zone.
    class Collisions < Data.define(:arrows, :obstacles)
      # A box on the canvas, from its left and top to its right and bottom.
      Rect = Data.define(:left, :top, :right, :bottom) do
        def overlap?(other) = left < other.right && right > other.left && top < other.bottom && bottom > other.top
      end

      def list = arrows.each_with_index.flat_map { |arrow, at| report(arrow, at) }

      private

      def report(arrow, at) = named(arrow).map { |name| "arrow #{at} crosses #{name}" }

      def named(arrow) = obstacles.keys.select { |name| struck?(arrow, name) }

      def struck?(arrow, name) = arrow.reaches.any? { |rect| Rect.new(*rect).overlap?(Rect.new(*obstacles.fetch(name))) }
    end
  end
end
