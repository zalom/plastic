# frozen_string_literal: true

module CommandReference
  module Dsl
    # The command class beside what each part of it declares.
    class DeclareCommand < CodeDrawing
      PARTS = [
        [/^class /, "THE COMMAND", :command],
        [/^\s*(intent_subject|node_subject|subject|argument|option)\b/, "INPUTS", :inputs],
        [/^\s*(reads|writes)\b/, "GRAPHS", :graphs],
        [/^\s*def call\b/, "BEFORE THE CHAIN", :before],
        [/^\s*workflow\b/, "THE CHAIN", :chain]
      ].freeze

      def initialize(page, rows)
        super(rows)
        @page = page
      end

      private

      def title = "How the plastic #{@page.words} command class is declared"

      def chars = 72

      def gap = 24

      def side = 72

      def notes = PARTS.filter_map { |pattern, tag, key| part(pattern, tag, key) }

      def part(pattern, tag, key)
        row = rows.index { |each| each.text.match?(pattern) }
        Note.new(row, tag, send(key), "card", "tag tag-end") if row
      end

      def command = ["plastic #{@page.words}", "a Routine: it runs a chain"]

      def inputs = ["what it takes", *@page.arguments.map { |arg| "#{arg.label}  #{arg.text}" }, *@page.options.map(&:switch)]

      def graphs = ["graphs it reads and writes", *@page.graph_lines]

      def before = ["a check of its own", "a usage error exits 2"]

      def chain = ["#{@page.flows.size} workflows", "starts at :#{@page.entry}"]
    end
  end
end
