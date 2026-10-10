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
  end
end
