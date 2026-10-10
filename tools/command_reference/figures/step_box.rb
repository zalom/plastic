# frozen_string_literal: true

module CommandReference
  module Figures
    # One step of a workflow, with the box of the stop it can cause on its right.
    class StepBox
      WIDE = 420
      STOP_TAGS = { refusal: "STOPS, EXIT 3, REFUSED", failure: "STOPS, EXIT 1, FAILED" }.freeze
      # How one kind of row looks: its tag, its box and its lines.
      Voice = Data.define(:tag, :tag_css, :box_css, :line_css, :checks)
      VOICES = {
        read: Voice.new("READ", "tag tag-muted", "card", "t", false),
        gate: Voice.new("GATE", "tag tag-muted", "card", "tm", false),
        step: Voice.new("STEP", "tag tag-muted", "card", "t", true),
        agent: Voice.new("AGENT STEP", "tag tag-agent", "lane-agent", "t", true)
      }.freeze

      def initialize(drawing, row)
        @drawing = drawing
        @row = row
        @voice = VOICES.fetch(row.kind)
      end

      def draw(top)
        frame = Box.new(Workflow::SPINE, top, WIDE, height)
        @drawing.rect(frame, @voice.box_css)
        annotate(frame)
        connector(frame.foot)
        frame.bottom
      end

      private

      def connector(foot) = @drawing.wire([foot, foot.shift(0, 10)])

      def annotate(frame)
        heading(frame)
        body(frame)
        stop(frame) if @row.stops
      end

      def height = [30 + words.size * 15 + check.size * 14, stop_height].max

      def words = @words ||= Words.wrap(@row.headline, 56)

      def check = @check ||= @voice.checks ? Words.wrap("done when #{@row.check}", 52) : []

      def reason = @reason ||= Words.wrap(@row.reason, 30)

      def stop_height = @row.stops ? 28 + reason.size * 14 : 0

      def heading(frame)
        @drawing.text(frame.at(10, 15), @voice.tag, @voice.tag_css)
        @drawing.text(frame.at(WIDE - 10, 15).ending, @row.location, "tm tag-muted")
      end

      def body(frame)
        @drawing.roomy(frame.at(10, 32), words, @voice.line_css)
        @drawing.paragraph(frame.at(10, 32 + words.size * 15), check, "tm")
      end

      def stop(frame)
        kind = @row.stops
        panel = Box.new(frame.right + 30, frame.top, 270, stop_height)
        @drawing.wire([frame.at(WIDE, 18), frame.at(WIDE + 28, 18)], "wire-#{kind}")
        @drawing.rect(panel, "stop-#{kind}")
        stop_words(panel, kind)
      end

      def stop_words(panel, kind)
        @drawing.text(panel.at(10, 15), STOP_TAGS.fetch(kind), "tag tag-#{kind}")
        @drawing.paragraph(panel.at(10, 31), reason, "tm")
      end
    end
  end
end
