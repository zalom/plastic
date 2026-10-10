# frozen_string_literal: true

module ArchitectureFigures
  class Diagram
    # The places where an arrow or its note runs through a card or the title of a zone.
    class Collisions < Data.define(:arrows, :obstacles)
      def list = arrows.each_with_index.flat_map { |arrow, at| hits(arrow).map { |name| "arrow #{at} crosses #{name}" } }

      private

      def hits(arrow)
        reaches = arrow.segments.map { |(ax, ay), (bx, by)| [[ax, bx].min, [ay, by].min, [ax, bx].max, [ay, by].max] }
        (reaches + arrow.note_bounds).flat_map { |rect| obstacles.select { |_name, found| overlap?(rect, found) }.keys }.uniq
      end

      def overlap?(one, other) = one[0] < other[2] && one[2] > other[0] && one[1] < other[3] && one[3] > other[1]
    end
  end
end
