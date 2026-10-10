# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A line with an arrowhead and a note on its longest stretch.
    class Arrow < Data.define(:points, :note, :dashed)
      def markup(id) = [path(id), *words].join("\n")

      def segments = points.each_cons(2).to_a

      def note_bounds = note.each_with_index.map { |line, row| spot(row).then { |across, down, _| [across - (line.size * 3.3), down - 10, across + (line.size * 3.3), down + 3] } }

      private

      def path(id) = %(<path class="flow" d="#{points.each_with_index.map { |(px, py), at| "#{at.zero? ? "M" : "L"} #{px} #{py}" }.join(" ")}"#{' stroke-dasharray="4 3"' if dashed} marker-end="url(##{id}-arrow)"/>)

      def words = note.each_with_index.map { |line, row| Shapes.text(spot(row), "al", line) }

      def longest = points.each_cons(2).max_by { |(px, py), (qx, qy)| (qx - px).abs + (qy - py).abs }

      def level? = longest.map(&:last).uniq.one?

      def lift(row) = level? ? -7 - (13 * (note.size - 1 - row)) : 4 + (13 * row)

      def spot(row)
        (ax, ay), (bx, by) = longest
        [((ax + bx) / 2.0).round, (((ay + by) / 2.0) + lift(row)).round, "middle"]
      end
    end
  end
end
