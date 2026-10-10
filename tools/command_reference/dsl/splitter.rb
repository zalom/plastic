# frozen_string_literal: true

module CommandReference
  module Dsl
    # Finds the places a statement may break: after a top-level comma, or before a trailing `if`.
    class Splitter
      BREAKS = { ", " => [1, 2], " if " => [3, 4] }.freeze

      def initialize(text)
        @text = text
        @depth = 0
        @quoted = false
      end

      def pieces
        cuts = self.cuts
        ([0] + cuts.map(&:last)).zip(cuts.map(&:first) + [@text.size]).map { |from, to| @text[from...to] }
      end

      def cuts = @cuts ||= @text.each_char.with_index.filter_map { |char, index| cut(char, index) }

      private

      def cut(char, index)
        quote = char == '"'
        @quoted = !@quoted if quote
        return if quote || @quoted

        nest(char)
        break_at(index) if @depth.zero?
      end

      def nest(char)
        @depth += 1 if "([{".include?(char)
        @depth -= 1 if ")]}".include?(char)
      end

      def break_at(index)
        token, offsets = BREAKS.find { |text, _| @text[index, text.size] == text }
        offsets.map { |offset| index + offset } if token
      end
    end
  end
end
