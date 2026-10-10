# frozen_string_literal: true

module CommandReference
  module Figures
    # How a call moves from workflow to workflow: one box per workflow, one wire per edge.
    class Chain
      BOX_W = 180
      BOX_H = 56
      GAP = 24
      RISE = 64

      def initialize(page)
        @page = page
      end

      def canvas
        return Call.new(@page).canvas if @page.flows.empty?

        drawing = Canvas.new(width, "The chain of plastic #{@page.words}")
        @page.edges.each { |edge| wire(drawing, edge) }
        @page.flows.each { |flow| box(drawing, flow) }
        @page.flows.each { |flow| pill(drawing, flow) if ends?(flow) }
        drawing
      end

      private

      def width = [layers.map(&:size).max * (BOX_W + GAP) + GAP, 480].max

      def place = @place ||= layers.each_with_index.flat_map { |keys, depth| spread(keys, depth) }.to_h

      def spread(keys, depth)
        left = (width - (keys.size * (BOX_W + GAP) - GAP)) / 2
        keys.each_with_index.map { |key, index| [key, [left + index * (BOX_W + GAP), 16 + depth * (BOX_H + RISE)]] }
      end

      def layers
        @layers ||= @page.flows.map(&:key).group_by { |key| depth.fetch(key, 0) }.sort.map(&:last)
      end

      def depth
        @depth ||= @page.flows.each_with_object({ @page.entry => 0 }) do |flow, found|
          @page.edges.select { |edge| edge.from == flow.key }.each { |edge| found[edge.to] = [found.fetch(edge.to, 0), found.fetch(flow.key, 0) + 1].max }
        end
      end

      def wire(drawing, edge)
        from_x, from_y = place.fetch(edge.from)
        to_x, to_y = place.fetch(edge.to)
        mid = from_y + BOX_H + RISE / 2
        drawing.wire([[from_x + BOX_W / 2, from_y + BOX_H], [from_x + BOX_W / 2, mid], [to_x + BOX_W / 2, mid], [to_x + BOX_W / 2, to_y]])
        drawing.text(to_x + BOX_W / 2 + 6, to_y - 10, label(edge), "tm tag-muted")
      end

      def label(edge) = edge.outcomes.compact.empty? ? "every outcome" : edge.outcomes.map { |name| ":#{name}" }.join(" ")

      def box(drawing, flow)
        x, y = place.fetch(flow.key)
        drawing.rect(x, y, BOX_W, BOX_H, "lane-#{flow.lane}")
        drawing.text(x + 10, y + 16, "#{flow.lane.upcase} WORKFLOW", (flow.lane == "agent") ? "tag tag-agent" : "tag tag-code")
        drawing.text(x + 10, y + 35, Words.short(flow.klass), "tb")
        drawing.text(x + 10, y + 50, ":#{flow.key}", "tm")
      end

      def ends?(flow) = flow.outcomes.any? { |outcome| outcome.to == :noop }

      def pill(drawing, flow)
        x, y = place.fetch(flow.key)
        top = y + BOX_H + 22
        drawing.wire([[x + BOX_W / 2, y + BOX_H], [x + BOX_W / 2, top]])
        drawing.rect(x + BOX_W / 2 - 70, top, 140, 24, "end", rx: 12)
        drawing.text(x + BOX_W / 2, top + 16, ending_words(flow), "tag tag-end", anchor: "middle")
      end

      def ending_words(flow) = (flow.lane == "agent") ? "hands off, exit #{exit_of(flow)}" : "finishes, exit 0"

      def exit_of(flow) = flow.outcomes.find { |outcome| outcome.to == :noop }.exit_code
    end
  end
end
