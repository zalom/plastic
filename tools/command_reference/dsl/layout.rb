# frozen_string_literal: true

module CommandReference
  module Dsl
    # Wraps a statement longer than a width after a top-level comma, and cuts what still does not fit.
    class Layout
      def initialize(width)
        @width = width
      end

      def rows(code_rows) = code_rows.flat_map { |row| row.spread(self) }

      def lines(text) = (text.size <= @width) ? [text] : Wrapper.new(text, @width).lines
    end

    # Packs the pieces of one statement into lines no wider than a width.
    class Wrapper
      def initialize(text, width)
        @indent = text[/\A */]
        @pieces = Splitter.new(text.strip).pieces
        @width = width
        @packed = []
      end

      def lines
        @pieces.each { |piece| add(piece) }
        @packed.map { |line| Fitter.new(line, @width).to_s }
      end

      private

      def add(piece) = @packed.empty? ? @packed << "#{@indent}#{piece}" : place(piece)

      def place(piece) = fits?(piece) ? @packed[-1] = "#{@packed.last} #{piece}" : @packed << "#{@indent}  #{piece}"

      def fits?(piece) = @packed.last.size + 1 + piece.size <= @width
    end

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
