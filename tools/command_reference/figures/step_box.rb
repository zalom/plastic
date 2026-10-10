# frozen_string_literal: true

module CommandReference
  module Figures
    # One step of a workflow, with the box of the stop it can cause on its right.
    class StepBox
      WIDE = 420
      TAGS = { read: "READ", gate: "GATE", step: "STEP", agent: "AGENT STEP" }.freeze

      def initialize(drawing, flow, row)
        @drawing = drawing
        @flow = flow
        @row = row
      end

      def draw(top)
        height = [30 + words.size * 15 + check.size * 14, stop_height].max
        @drawing.rect(Workflow::SPINE, top, WIDE, height, (@row.kind == :agent) ? "lane-agent" : "card")
        tags(top)
        lines(top)
        stop(top) if @row.stops
        @drawing.wire([[Workflow::SPINE + WIDE / 2, top + height], [Workflow::SPINE + WIDE / 2, top + height + 10]])
        top + height
      end

      private

      def words = @words ||= Words.wrap((@row.kind == :gate) ? "passes when #{@row.check}" : @row.name, 56)

      def check = @check ||= %i[step agent].include?(@row.kind) ? Words.wrap("done when #{@row.check}", 52) : []

      def tags(top)
        @drawing.text(Workflow::SPINE + 10, top + 15, TAGS.fetch(@row.kind), (@row.kind == :agent) ? "tag tag-agent" : "tag tag-muted")
        @drawing.text(Workflow::SPINE + WIDE - 10, top + 15, "#{File.basename(@row.file)}:#{@row.line}", "tm tag-muted", anchor: "end")
      end

      def lines(top)
        words.each_with_index { |line, at| @drawing.text(Workflow::SPINE + 10, top + 32 + at * 15, line, (@row.kind == :gate) ? "tm" : "t") }
        check.each_with_index { |line, at| @drawing.text(Workflow::SPINE + 10, top + 32 + words.size * 15 + at * 14, line, "tm") }
      end

      def reason = @reason ||= Words.wrap((@row.kind == :gate) ? @row.name : "the step ran and its done check still fails", 30)

      def stop_height = @row.stops ? 28 + reason.size * 14 : 0

      def stop(top)
        edge = Workflow::SPINE + WIDE
        @drawing.wire([[edge, top + 18], [edge + 28, top + 18]], "wire-#{@row.stops}")
        @drawing.rect(edge + 30, top, 270, stop_height, "stop-#{@row.stops}")
        @drawing.text(edge + 40, top + 15, (@row.stops == :refusal) ? "STOPS, EXIT 3, REFUSED" : "STOPS, EXIT 1, FAILED", "tag tag-#{@row.stops}")
        reason.each_with_index { |line, at| @drawing.text(edge + 40, top + 31 + at * 14, line, "tm") }
      end
    end
  end
end
