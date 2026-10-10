# frozen_string_literal: true

module CommandReference
  module Dsl
    # Code on the left of a drawing and a note beside each part of it that explains it.
    class CodeDrawing
      WIDTH = 940

      def initialize(rows)
        @rows = Layout.new(chars).rows(rows)
      end

      def canvas = Figures::Canvas.new(WIDTH, title).tap { |drawing| paint(drawing) }

      private

      attr_reader :rows

      def paint(drawing)
        panel = CodePanel.new(drawing, rows, chars)
        bases = panel.draw(Figures::Point.new(16, 16))
        Notes.new(drawing, bases).draw(column(panel.width), notes)
      end

      def column(panel_width) = Figures::Box.new(16 + panel_width + gap, 0, WIDTH - panel_width - side, 0)
    end

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

    # A code workflow beside what each of its lines does when it runs.
    class CodeFlow < CodeDrawing
      NOTES = {
        "sets" => Note.new(nil, "FACTS", ["filled in by the steps"], "card", "tag tag-muted"),
        "read" => Note.new(nil, "READ", ["runs on every call"], "card", "tag tag-muted"),
        "forget_stop" => Note.new(nil, "READ", ["clears an old stop"], "card", "tag tag-muted"),
        "step" => Note.new(nil, "STEP", ["runs until done: holds"], "lane-code", "tag tag-code")
      }.freeze
      SPECIAL = %w[gate outcome].freeze
      GATES = {
        true => Note.new(nil, "GATE", ["false: exit 3, the owner's step"], "stop-refusal", "tag tag-refusal"),
        false => Note.new(nil, "GATE", ["false: exit 1, the agent fixes it"], "stop-failure", "tag tag-failure")
      }.freeze

      def initialize(name, rows)
        super(rows)
        @name = name
      end

      def self.gate(text) = GATES.fetch(text.include?("stops: :refusal"))

      def self.outcome(text) = Note.new(nil, "OUTCOME", [text.include?("if:") ? "when its if: holds" : "the fallback"], "end", "tag tag-end")

      private

      def title = "How the #{@name} code workflow is declared and how it runs"

      def chars = 78

      def gap = 20

      def side = 52

      def table = NOTES

      def notes = rows.each_index.select { |index| rows[index].number }.filter_map { |index| noted(index) }

      def noted(index) = note(statement(index))&.with(row: index)

      def statement(index)
        [rows[index], *rows[index + 1..].take_while { |row| !row.number && !row.gap? }].map(&:text).join(" ")
      end

      def note(text)
        word = text.strip.split(/[\s(]/).first.to_s
        table.fetch(word) { SPECIAL.include?(word) ? self.class.public_send(word, text) : nil }
      end
    end

    # An agent workflow beside what a call prints for each step.
    class AgentFlow < CodeFlow
      NOTES = {
        "step" => Note.new(nil, "STEP", ["printed while its done: check fails"], "lane-agent", "tag tag-agent")
      }.freeze

      def self.outcome(text) = Note.new(nil, "OUTCOME", [text.include?(":handoff") ? "ends the call while a step is left" : "ends the call once every check holds"], "end", "tag tag-end")

      private

      def table = NOTES
    end
  end
end
