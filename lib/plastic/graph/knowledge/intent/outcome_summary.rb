# frozen_string_literal: true

require_relative "../intent"

module Plastic
  module Graph
    module Knowledge
      class Intent
        # The summary of an intent outcome: the text between the title and the first section. A new summary replaces
        # the old one and keeps the title and every section. The summary holds no heading, because the sections are
        # written by `plastic intent note`.
        class OutcomeSummary
          STARTER = "# Outcome"
          TITLE = /\A#\s/
          HEADING = /\A {0,3}\#{1,6}(?:\s|\z)/

          # Why `text` cannot be a summary, else nil.
          def self.problem(text)
            heading = text.lines.map(&:chomp).find { |line| HEADING.match?(line) }
            return "the summary holds the heading '#{heading.strip}'; the summary is plain text, and plastic intent note writes the lines of each section" if heading

            "the summary is empty; write what the work delivered or why it stopped" if text.strip.empty?
          end

          def self.for(body)
            first, *rest = body.to_s.lines.map(&:chomp)
            TITLE.match?(first.to_s) ? new(first, rest) : new(STARTER, [first, *rest].compact)
          end

          def initialize(title, lines)
            @title = title
            @sections = lines.drop(lines.index { |line| HEADING.match?(line) } || lines.size)
          end

          # The whole outcome with `text` as its summary.
          def replace(text)
            summary = OutcomeSummary.trimmed(text.lines.map(&:chomp))
            "#{[@title, "", *summary, *(["", *@sections] if @sections.any?)].join("\n")}\n"
          end

          def self.trimmed(lines)
            blank = ->(line) { line.strip.empty? }
            lines.drop_while(&blank).reverse.drop_while(&blank).reverse
          end
        end
      end
    end
  end
end
