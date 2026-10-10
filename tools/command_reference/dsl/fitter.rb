# frozen_string_literal: true

module CommandReference
  module Dsl
    # Cuts a line to a width: long strings shortened, then braces folded away, then the end cut off.
    class Fitter
      BRACES = /\{ (?!… \})[^{}]* \}/
      STRING = /"[^"]*"/

      def initialize(text, width)
        @text = text
        @width = width
      end

      def to_s
        shorten
        squash
        long? ? "#{@text[0, @width - 1]}…" : @text
      end

      private

      def long? = @text.size > @width

      def shorten
        @text = trim(longest) while long? && longest.to_s.size > 12
      end

      def squash
        @text = @text.sub(BRACES, "{ … }") while long? && @text.match?(BRACES)
      end

      def longest = @text.scan(STRING).max_by(&:size)

      def trim(string) = @text.sub(string, "#{string[0, [string.size - (@text.size - @width) - 2, 8].max]}…\"")
    end
  end
end
