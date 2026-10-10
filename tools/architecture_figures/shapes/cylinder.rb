# frozen_string_literal: true

module ArchitectureFigures
  module Shapes
    # A database drawn as a cylinder.
    class Cylinder < Data.define(:left, :top, :width, :name, :lines, :tone)
      include Anchored

      def height = 52 + (15 * lines.size)

      def markup(_id) = [body, rim, caption, *notes].join("\n")

      private

      def radius = width / 2.0

      def middle = left + radius

      def cap = top + 9

      def base = bottom - 9

      def body = %(<path class="box" d="M #{left} #{cap} L #{left} #{base} A #{radius} 9 0 0 0 #{right} #{base} L #{right} #{cap} Z"/>)

      def rim = %(<ellipse class="box" cx="#{middle}" cy="#{cap}" rx="#{radius}" ry="9" style="stroke: #{Palette.color(tone)}"/>)

      def caption = Shapes.text([middle, top + 36, "middle"], "m", name)

      def notes = lines.each_with_index.map { |line, row| Shapes.text([middle, top + 54 + (15 * row), "middle"], "s", line) }
    end
  end
end
