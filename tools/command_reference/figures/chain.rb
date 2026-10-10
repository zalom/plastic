# frozen_string_literal: true

module CommandReference
  module Figures
    # How a call moves from workflow to workflow: one box per workflow, one wire per edge.
    class Chain
      def initialize(page)
        @page = page
        @layout = ChainLayout.new(page.flows, page.edges, page.entry)
        @drawing = Canvas.new(@layout.width, "The chain of plastic #{page.words}")
      end

      def canvas = @page.flows.empty? ? Call.new(@page).canvas : (@canvas ||= paint)

      private

      def paint
        wires
        boxes
        pills
        @drawing
      end

      def wires = @page.edges.each { |edge| wire(edge) }

      def boxes = @page.flows.each { |flow| box(flow) }

      def pills = @page.flows.select(&:closing).each { |flow| pill(flow) }

      def wire(edge)
        @drawing.wire(@layout.route(edge))
        @drawing.text(@layout.frame(edge.to).head.shift(6, -10), edge.words, "tm tag-muted")
      end

      def box(flow)
        frame = @layout.frame(flow.key)
        @drawing.rect(frame, "lane-#{flow.lane}")
        caption(frame, flow)
      end

      def caption(frame, flow)
        heading, name, key = flow.captions
        @drawing.text(frame.at(10, 16), heading, flow.agent? ? "tag tag-agent" : "tag tag-code")
        @drawing.text(frame.at(10, 35), name, "tb")
        @drawing.text(frame.at(10, 50), key, "tm")
      end

      def pill(flow)
        foot = @layout.frame(flow.key).foot
        tip = foot.shift(0, 22)
        @drawing.wire([foot, tip])
        ending(tip, flow)
      end

      def ending(tip, flow)
        @drawing.rect(tip.box(140, 24), "end", rx: 12)
        @drawing.text(tip.shift(0, 16).middle, flow.closing_words, "tag tag-end")
      end
    end
  end
end
