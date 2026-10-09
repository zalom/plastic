# frozen_string_literal: true

require_relative "output"
require_relative "readable"

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

      # Prints the rows now, so an error line can follow them and the closing
      # lines follow the error.
      def flush_rows(_project = nil)
        return self if @flushed || @rows_flushed

        @rows_flushed = true
        lines = row_lines
        out.puts(lines) unless lines.empty?
        self
      end

      private

      def print_answer(project)
        rows = @rows_flushed ? [] : row_lines
        closing = result.closing_lines(project)
        lines = (rows.empty? || closing.empty?) ? rows + closing : [*rows, "", *closing]
        out.puts(lines) unless lines.empty?
      end

      def row_lines
        width = label_width
        result.rows.flat_map { |label, value| self.class.lines_for(label, items_of(value), width) }
      end

      def items_of(value) = Readable.structured?(value) ? Readable.lines(value) : Array(value)

      def label_width
        widths = result.rows.reject { |_label, value| items_of(value).empty? }.map { |label, _value| label.length }
        widths.empty? ? 0 : widths.max + LABEL_GAP
      end
    end
  end
end
