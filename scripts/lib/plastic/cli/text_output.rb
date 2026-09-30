# frozen_string_literal: true

require_relative "output"

module Plastic
  class CLI
    # The answer as lines: the rows lined up on the widest label, a blank
    # line, then next: and because:. Raw text prints at once.
    class TextOutput < Output
      LABEL_GAP = 2

      # The label goes on the first line of a value only.
      def self.lines_for(label, items, width)
        items.each_with_index.map { |item, index| "#{(index.zero? ? label : "").ljust(width)}#{item}" }
      end

      def raw(text) = tap { out.puts(text) }

      private

      def print_answer(project)
        rows = row_lines
        closing = result.closing_lines(project)
        lines = (rows.empty? || closing.empty?) ? rows + closing : [*rows, "", *closing]
        out.puts(lines) unless lines.empty?
      end

      def row_lines
        width = label_width
        result.rows.flat_map { |label, value| self.class.lines_for(label, Array(value), width) }
      end

      def label_width
        widths = result.rows.reject { |_label, value| Array(value).empty? }.map { |label, _value| label.length }
        widths.empty? ? 0 : widths.max + LABEL_GAP
      end
    end
  end
end
