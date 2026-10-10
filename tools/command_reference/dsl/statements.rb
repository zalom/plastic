# frozen_string_literal: true

module CommandReference
  module Dsl
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
