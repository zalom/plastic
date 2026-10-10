# frozen_string_literal: true

module CommandReference
  module Dsl
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
  end
end
