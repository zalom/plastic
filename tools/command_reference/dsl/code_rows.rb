# frozen_string_literal: true

module CommandReference
  module Dsl
    # One line of code with its file line number; a gap row stands for code left out.
    CodeRow = Data.define(:number, :text) do
      def gap? = text == "⋯"

      def blank? = text.strip.empty?

      def vacant? = blank? || gap?

      def head = text.strip.split(/[\s(]/).first.to_s

      def kept?(words) = blank? || text.start_with?("class ", "end") || words.include?(head)

      def spread(layout) = layout.lines(text).each_with_index.map { |line, at| CodeRow.new(at.zero? ? number : nil, line) }
    end

    # The lines of one class in a file, unindented to the class line, with their file line numbers.
    class ClassRows
      def initialize(lines, name)
        @lines = lines
        @name = name
      end

      def rows = (start..stop).map { |index| CodeRow.new(index + 1, @lines[index].delete_prefix(indent)) }

      private

      def start = @start ||= @lines.index { |text| text.match?(/^\s*class #{@name}\b/) }

      def indent = @indent ||= @lines[start][/\A */]

      def stop = @stop ||= (start...@lines.size).find { |index| @lines[index] == "#{indent}end" }
    end

    # One row per statement: continued lines joined, blocks shortened, other code left out behind a gap row.
    class Statements
      WORDS = %w[workflow on option argument intent_subject node_subject subject reads writes sets read gate step outcome forget_stop].freeze
      BLOCK = /\bdo( \|[^|]*\|)?\s*\z/
      METHOD = /^\s*def [^=]*\z/
      SHORTENABLE = Regexp.union(BLOCK, METHOD)

      def initialize(rows)
        @rows = rows
        @at = 0
      end

      def rows
        @at = 0
        self.class.squeeze(statements.map { |row| row.kept?(WORDS) ? row : CodeRow.new(nil, "⋯") })
      end

      def self.squeeze(rows)
        rows.chunk_while { |first, second| first.vacant? && second.vacant? }.map { |run| run.find(&:gap?) || run.first }
      end

      private

      def statements = [].tap { |found| found << next_row while @at < @rows.size }

      def next_row
        first = @rows[@at]
        text = shortened(continued(first.text))
        @at += 1
        CodeRow.new(first.number, text)
      end

      def continued(text)
        stripped = text.rstrip
        return text unless stripped.end_with?(",") && @rows[@at + 1]

        @at += 1
        continued("#{stripped} #{@rows[@at].text.strip}")
      end

      def shortened(text)
        return text unless @at.positive? && text.match?(SHORTENABLE)

        indent = text[/\A */]
        @at = (@at + 1...@rows.size).find { |index| @rows[index].text == "#{indent}end" } || @at
        text.sub(BLOCK, "do … end")
      end
    end
  end
end
