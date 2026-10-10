# frozen_string_literal: true

module CommandReference
  module Dsl
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

      def canvas = Figures::Canvas.new(@values.size * 226 + 20, "The four ways a plastic call ends, with their exit codes").tap { |drawing| paint(drawing) }

      private

      def paint(drawing)
        @values.each_with_index { |value, index| EndCard.new(drawing, value).draw(16 + index * 226) }
      end
    end

    # One end value as a card: its exit code, its name, what it means and who acts.
    class EndCard
      def initialize(drawing, value)
        @drawing = drawing
        @value = value
        @color, @who = EndValues::WHO.fetch(value.fetch(:name))
      end

      def draw(left)
        frame = Figures::Box.new(left, 16, 214, 176)
        @drawing.rect(frame, "card")
        @drawing.rect(Figures::Box.new(left + 1, 17, 212, 5), "tag-#{@color}", rx: 2)
        heading(frame)
        meaning(frame)
      end

      private

      def heading(frame)
        @drawing.text(frame.at(12, 24), "EXIT", "tag tag-muted")
        @drawing.text(frame.at(12, 60), @value.fetch(:exit_code), "big tag-#{@color}")
        @drawing.text(frame.at(50, 58), @value.fetch(:name), "tb")
      end

      def meaning(frame)
        @drawing.paragraph(frame.at(12, 82), Words.wrap(@value.fetch(:words), 32), "t")
        @drawing.paragraph(frame.at(12, 118), Words.wrap(@who, 32), "tm tag-muted")
      end
    end
  end
end
