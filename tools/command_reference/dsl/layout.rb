# frozen_string_literal: true

module CommandReference
  module Dsl
    # Wraps a statement longer than a width after a top-level comma, and cuts what still does not fit.
    class Layout
      def initialize(width)
        @width = width
      end

      def rows(code_rows)
        code_rows.flat_map { |row| lines(row.text).each_with_index.map { |text, at| CodeRow.new(at.zero? ? row.number : nil, text) } }
      end

      def lines(text)
        return [text] if text.size <= @width

        indent = text[/\A */]
        pieces = pieces(text.strip)
        lines = ["#{indent}#{pieces.shift}"]
        pieces.each { |piece| add(lines, piece, indent) }
        lines.map { |line| fit(line) }
      end

      private

      def add(lines, piece, indent)
        if lines.last.size + 1 + piece.size <= @width
          lines[-1] = "#{lines.last} #{piece}"
        else
          lines << "#{indent}  #{piece}"
        end
      end

      def pieces(text)
        cuts = Splitter.new(text).cuts
        ([0] + cuts.map(&:last)).zip(cuts.map(&:first) + [text.size]).map { |from, to| text[from...to] }
      end

      def fit(line)
        line = shorten(line)
        line = line.sub(/\{ (?!… \})[^{}]* \}/, "{ … }") while line.size > @width && line.match?(/\{ (?!… \})[^{}]* \}/)
        (line.size > @width) ? "#{line[0, @width - 1]}…" : line
      end

      def shorten(text)
        while text.size > @width && (longest = text.scan(/"[^"]*"/).max_by(&:size)) && longest.size > 12
          text = text.sub(longest, "#{longest[0, [longest.size - (text.size - @width) - 2, 8].max]}…\"")
        end
        text
      end
    end

    # Finds the places a statement may break: after a top-level comma, or before a trailing `if`.
    class Splitter
      def initialize(text)
        @text = text
      end

      def cuts
        @depth = 0
        @quoted = false
        @text.each_char.with_index.filter_map { |char, index| cut(char, index) }
      end

      private

      def cut(char, index)
        return quote(char) if @quoted || char == '"'

        @depth += "([{".include?(char) ? 1 : 0
        @depth -= ")]}".include?(char) ? 1 : 0
        break_at(char, index) if @depth.zero?
      end

      def quote(char)
        @quoted = !@quoted if char == '"'
        nil
      end

      def break_at(char, index)
        return [index + 1, index + 2] if char == "," && @text[index + 1] == " "

        [index + 3, index + 4] if @text[index, 4] == " if "
      end
    end
  end
end
