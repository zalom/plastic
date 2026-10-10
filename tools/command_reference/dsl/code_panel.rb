# frozen_string_literal: true

require "strscan"

module CommandReference
  module Dsl
    # Draws rows of code on a canvas with their file line numbers, and tells where each row sits.
    class CodePanel
      CHAR = 7.25
      LINE = 19
      GUTTER = 38
      TOKENS = [
        [/"(?:[^"\\]|\\.)*"?/, "cx-s"], [/#.*/, "cx-c"], [/:[a-z_]+[?!]?/, "cx-y"], [/[a-z_]+:(?!:)/, "cx-y"],
        [/->|\b(?:class|def|do|end|if|unless|raise|super|true|false|nil|self)\b/, "cx-k"],
        [/\b(?:#{Statements::WORDS.join("|")})\b/, "cx-w"], [/[A-Z]\w*(?:::[A-Z]\w*)*/, "cx-t"], [/[a-z_]\w*[?!]?/, nil], [/./, nil]
      ].freeze

      def initialize(canvas, rows, chars)
        @canvas = canvas
        @rows = rows
        @chars = chars
      end

      def width = (GUTTER + @chars * CHAR + 12).ceil

      def draw(origin)
        @canvas.rect(Figures::Box.new(origin.left, origin.top, width, @rows.size * LINE + 14), "codebox")
        @rows.each_with_index.map { |row, index| line(row, origin.shift(0, 20 + index * LINE)).top }
      end

      private

      def line(row, base)
        number(row.number, base)
        start = base.shift(GUTTER, 0)
        row.gap? ? @canvas.text(start, "⋯ other code", "cx-n") : @canvas.raw(Tokens.new(row.text).svg(start), base.top + 6)
        base
      end

      def number(found, base) = (@canvas.text(base.shift(GUTTER - 10, 0).ending, found, "cx-n") if found)
    end

    # The colored pieces of one line of code.
    class Tokens
      def initialize(text)
        @indent = text[/\A */].size
        @scanner = StringScanner.new(text.lstrip)
      end

      def svg(start) = %(<text x="#{start.left + @indent * CodePanel::CHAR}" y="#{start.top}" class="cx">#{spans}</text>)

      def spans = runs.map { |css, words| css ? %(<tspan class="#{css}">#{words}</tspan>) : words }.join

      private

      def runs
        parts = []
        parts << piece until @scanner.eos?
        parts.chunk_while { |first, second| first.first == second.first }.map { |run| [run.first.first, CGI.escapeHTML(run.map(&:last).join)] }
      end

      def piece
        css = CodePanel::TOKENS.find { |pattern, _| @scanner.scan(pattern) }.last
        [css, @scanner.matched]
      end
    end
  end
end
