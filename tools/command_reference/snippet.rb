# frozen_string_literal: true

module CommandReference
  # Cuts text out of kernel source: comment blocks, brace bodies and method bodies.
  module Snippet
    ENDLESS = /\Adef \S+( |\(.*\) )= /
    END_LINE = /\A\s*end\b/

    class << self
      def blocks(comment)
        comment.chunk { |text| kind_of(text) }.map { |kind, group| (kind == :code) ? code_block(group) : text_block(group) }
      end

      def brace_body(text, open)
        depth = 0
        close = (open...text.size).find do |index|
          depth += { "{" => 1, "}" => -1 }.fetch(text[index], 0)
          depth.zero?
        end
        text[(open + 1)...close].strip.gsub(/\s+/, " ")
      end

      def method_text(text)
        rows = text.lines
        first = rows.first.strip
        return first.sub(ENDLESS, "") if first.match?(ENDLESS)

        rows.first(rows.index { |row| row.match?(END_LINE) } + 1).map(&:strip).join(" ")
      end

      def method_lines(body)
        one_line = body.first.strip
        one_line.match?(ENDLESS) ? [one_line] : block_lines(body)
      end

      def comment(before)
        above = before.map(&:strip).reverse.take_while { |text| text.start_with?("#") }
        above.reverse.map { |text| text.sub(/\A# ?/, "") }.reject { |text| text.start_with?("frozen_string_literal") }
      end

      private

      def block_lines(body)
        indent = body.first[/\A */]
        body.first(body.index { |text| text == "#{indent}end" } + 1).map { |text| text.delete_prefix(indent) }
      end

      def kind_of(text)
        return if text.empty?

        text.start_with?("  ") ? :code : :text
      end

      def text_block(group) = [:text, group.join(" ")]

      def code_block(group) = [:code, group.map { |text| text.delete_prefix("  ") }.join("\n")]
    end
  end
end
