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

      def draw(x, y)
        @canvas.rect(x, y, width, @rows.size * LINE + 14, "codebox")
        @rows.each_with_index.map { |row, index| line(row, x, y + 20 + index * LINE) }
      end

      private

      def line(row, x, base)
        @canvas.text(x + GUTTER - 10, base, row.number, "cx-n", anchor: "end") if row.number
        (row.text == "⋯") ? @canvas.text(x + GUTTER, base, "⋯ other code", "cx-n") : @canvas.raw(code(x + GUTTER, base, row.text), base + 6)
        base
      end

      def code(x, base, text)
        %(<text x="#{x + text[/\A */].size * CHAR}" y="#{base}" class="cx">#{Tokens.new(text.lstrip).spans}</text>)
      end
    end

    # The colored pieces of one line of code.
    class Tokens
      def initialize(text)
        @scanner = StringScanner.new(text)
      end

      def spans = runs.map { |css, words| css ? %(<tspan class="#{css}">#{CGI.escapeHTML(words)}</tspan>) : CGI.escapeHTML(words) }.join

      private

      def runs
        parts = []
        parts << piece until @scanner.eos?
        parts.chunk_while { |first, second| first.first == second.first }.map { |run| [run.first.first, run.map(&:last).join] }
      end

      def piece
        css = CodePanel::TOKENS.find { |pattern, _| @scanner.scan(pattern) }.last
        [css, @scanner.matched]
      end
    end
  end
end
