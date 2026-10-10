# frozen_string_literal: true

module CommandReference
  module Dsl
    CodeRow = Data.define(:number, :text)

    # The lines of one class in a file, unindented to the class line, with their file line numbers.
    class ClassRows
      def initialize(lines, name)
        @lines = lines
        @name = name
      end

      def rows
        start = @lines.index { |text| text.match?(/^\s*class #{@name}\b/) }
        indent = @lines[start][/\A */]
        stop = (start...@lines.size).find { |index| @lines[index] == "#{indent}end" }
        (start..stop).map { |index| CodeRow.new(index + 1, @lines[index].delete_prefix(indent)) }
      end
    end

    # One row per statement: continued lines joined, blocks shortened, other code left out behind a gap row.
    class Statements
      WORDS = %w[workflow on option argument intent_subject node_subject subject reads writes sets read gate step outcome forget_stop].freeze
      BLOCK = /\bdo( \|[^|]*\|)?\s*\z/

      def initialize(rows)
        @rows = rows
      end

      def rows
        @at = 0
        found = []
        found << next_row while @at < @rows.size
        squeeze(found.map { |row| kept?(row) ? row : CodeRow.new(nil, "⋯") })
      end

      private

      def next_row
        first = @rows[@at]
        text = continued(first.text)
        text = folded(text) if @at.positive? && folds?(text)
        @at += 1
        CodeRow.new(first.number, text)
      end

      def continued(text)
        text = "#{text.rstrip} #{@rows[@at += 1].text.strip}" while text.rstrip.end_with?(",") && @rows[@at + 1]
        text
      end

      def folds?(text) = text.match?(BLOCK) || text.match?(/^\s*def [^=]*\z/)

      def folded(text)
        indent = text[/\A */]
        @at = (@at + 1...@rows.size).find { |index| @rows[index].text == "#{indent}end" } || @at
        text.sub(BLOCK, "do … end")
      end

      def kept?(row)
        word = row.text.strip.split(/[\s(]/).first.to_s
        row.text.strip.empty? || row.text.start_with?("class ", "end") || WORDS.include?(word)
      end

      def squeeze(rows)
        rows.chunk_while { |first, second| gap?(first) && gap?(second) }.map { |run| run.find { |row| row.text == "⋯" } || run.first }
      end

      def gap?(row) = row.text.strip.empty? || row.text == "⋯"
    end
  end
end
