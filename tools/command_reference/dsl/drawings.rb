# frozen_string_literal: true

module CommandReference
  module Dsl
    # The command class beside what each part of it declares.
    class DeclareCommand
      PARTS = [
        [/^class /, "THE COMMAND", :command],
        [/^\s*(intent_subject|node_subject|subject|argument|option)\b/, "INPUTS", :inputs],
        [/^\s*(reads|writes)\b/, "GRAPHS", :graphs],
        [/^\s*def call\b/, "BEFORE THE CHAIN", :before],
        [/^\s*workflow\b/, "THE CHAIN", :chain]
      ].freeze

      def initialize(page, rows)
        @page = page
        @rows = Layout.new(72).rows(rows)
      end

      def canvas
        drawing = Figures::Canvas.new(940, "How the plastic #{@page.words} command class is declared")
        panel = CodePanel.new(drawing, @rows, 72)
        bases = panel.draw(16, 16)
        Notes.new(drawing, bases.each_with_index.to_h { |base, at| [at, base] }).draw(16 + panel.width + 24, 940 - panel.width - 72, notes)
        drawing
      end

      private

      def notes
        PARTS.filter_map do |pattern, tag, key|
          row = @rows.index { |each| each.text.match?(pattern) }
          Note.new(row, tag, send(key), "card", "tag tag-end") if row
        end
      end

      def command = ["plastic #{@page.words}", "a Routine: it runs a chain"]

      def inputs = ["what it takes", *@page.arguments.map { |arg| "#{arg.label}  #{arg.text}" }, *@page.options.map(&:switch)]

      def graphs = ["graphs it reads and writes", *@page.klass.writes.map { |graph| "writes #{graph}" }, *@page.klass.reads.map { |graph| "reads #{graph}" }]

      def before = ["a check of its own", "a usage error exits 2"]

      def chain = ["#{@page.flows.size} workflows", "starts at :#{@page.entry}"]
    end

    # A code workflow beside what each of its lines does when it runs.
    class CodeFlow
      NOTES = {
        "sets" => ["FACTS", "filled in by the steps", "card", "tag tag-muted"],
        "read" => ["READ", "runs on every call", "card", "tag tag-muted"],
        "forget_stop" => ["READ", "clears an old stop", "card", "tag tag-muted"],
        "step" => ["STEP", "runs until done: holds", "lane-code", "tag tag-code"]
      }.freeze

      def initialize(name, rows)
        @name = name
        @rows = Layout.new(78).rows(rows)
      end

      def canvas
        drawing = Figures::Canvas.new(940, "How the #{@name} code workflow is declared and how it runs")
        panel = CodePanel.new(drawing, @rows, 78)
        bases = panel.draw(16, 16)
        Notes.new(drawing, bases.each_with_index.to_h { |base, at| [at, base] }).draw(16 + panel.width + 20, 940 - panel.width - 52, notes)
        drawing
      end

      private

      def notes
        @rows.each_index.filter_map do |index|
          found = note(statement(index))
          Note.new(index, found[0], [found[1]], found[2], found[3]) if @rows[index].number && found
        end
      end

      def statement(index)
        [@rows[index], *@rows[index + 1..].take_while { |row| row.number.nil? && row.text != "⋯" }].map(&:text).join(" ")
      end

      def note(text)
        word = text.strip.split(/[\s(]/).first.to_s
        return self.class::NOTES.fetch(word) if self.class::NOTES.key?(word)

        (word == "gate") ? gate(text) : (outcome(text) if word == "outcome")
      end

      def gate(text)
        refusal = text.include?("stops: :refusal")
        ["GATE", refusal ? "false: exit 3, the owner's step" : "false: exit 1, the agent fixes it", refusal ? "stop-refusal" : "stop-failure", "tag tag-#{refusal ? "refusal" : "failure"}"]
      end

      def outcome(text) = ["OUTCOME", text.include?("if:") ? "when its if: holds" : "the fallback", "end", "tag tag-end"]
    end

    # An agent workflow beside what a call prints for each step.
    class AgentFlow < CodeFlow
      NOTES = {
        "step" => ["STEP", "printed while its done: check fails", "lane-agent", "tag tag-agent"]
      }.freeze

      private

      def outcome(text) = ["OUTCOME", text.include?(":handoff") ? "ends the call while a step is left" : "ends the call once every check holds", "end", "tag tag-end"]
    end

    # The four values a call ends in, each with its exit code.
    class EndValues
      WHO = {
        "Finished" => [:end, "the next: line names the command to run"],
        "HandedOff" => [:agent, "the agent does the printed steps, then runs the call again"],
        "Failed" => [:failure, "the agent fixes what the last line names"],
        "Refused" => [:refusal, "the owner takes the step the line names"]
      }.freeze

      def initialize(values)
        @values = values
      end

      def canvas
        drawing = Figures::Canvas.new(16 * 2 + @values.size * 214 + (@values.size - 1) * 12, "The four ways a plastic call ends, with their exit codes")
        @values.each_with_index { |value, index| card(drawing, value, 16 + index * 226) }
        drawing
      end

      private

      def card(drawing, value, x)
        color, who = WHO.fetch(value.fetch(:name))
        drawing.rect(x, 16, 214, 176, "card")
        drawing.rect(x + 1, 17, 212, 5, "tag-#{color}", rx: 2)
        drawing.text(x + 12, 40, "EXIT", "tag tag-muted")
        drawing.text(x + 12, 76, value.fetch(:exit_code), "big tag-#{color}")
        drawing.text(x + 50, 74, value.fetch(:name), "tb")
        Words.wrap(value.fetch(:words), 32).each_with_index { |line, at| drawing.text(x + 12, 98 + at * 14, line, "t") }
        Words.wrap(who, 32).each_with_index { |line, at| drawing.text(x + 12, 134 + at * 14, line, "tm tag-muted") }
      end
    end
  end
end
