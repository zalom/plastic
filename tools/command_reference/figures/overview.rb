# frozen_string_literal: true

module CommandReference
  module Figures
    # How one call moves from workflow to workflow, in words: a card for each workflow and for each way the call ends.
    class Overview
      COLUMN = 266
      MARGIN = 24
      GAP = 26
      SIDED = Plate::WIDTH + 2 * (Sides::GAP + Sides::WIDTH)

      def initialize(page)
        @page = page
        @flows = page.flows.to_h { |flow| [flow.key, flow] }
        @onward = page.edges.group_by(&:from).transform_values { |edges| edges.sort_by { |edge| order.index(edge.to) } }
        @reasons = Reasons.new(page)
        @spans = {}
      end

      def canvas
        found = Canvas.new(width, "The workflows of one call of plastic #{@page.words}, in words")
        found.text(Point.new(MARGIN, 34), "One call of plastic #{@page.words}: its workflows and its endings", "tb")
        @canvas = found
        @plate = Plate.new(found)
        place(@page.entry, (width - span(@page.entry)) / 2, 56)
        found
      end

      private

      def order = @order ||= @page.flows.map(&:key)

      def width = [834, span(@page.entry) + 2 * MARGIN].max

      def span(key) = @spans[key] ||= [children_span(key), sided?(key) ? SIDED : COLUMN].max

      def children_span(key) = @onward.fetch(key, []).sum { |edge| span(edge.to) }

      def sided?(key) = Sides.needed?(FlowStops.new(@flows.fetch(key)), @onward.key?(key))

      def place(key, left, top)
        flow = @flows.fetch(key)
        box = flow_card(flow, left, top)
        stops = FlowStops.new(flow)
        below = Sides.new(@canvas, @plate).draw(box, stops, @onward.key?(key))
        @onward.key?(key) ? branch(box, left, key, below) : ending(box, stops.closing)
      end

      def flow_card(flow, left, top)
        lines = Plate.lines(flow.klass.summary)
        box = Box.new(left + span(flow.key) / 2 - Plate::WIDTH / 2, top, Plate::WIDTH, Plate.height(lines))
        box.tap { @plate.flow(box, flow, lines) }
      end

      def branch(box, left, key, below)
        bus = below + 22
        start = left + (span(key) - children_span(key)) / 2
        @onward.fetch(key).reduce(start) do |at, edge|
          descend(box, bus, edge, at)
          at + span(edge.to)
        end
      end

      def descend(box, bus, edge, at)
        center = at + span(edge.to) / 2
        bus_line(box, bus, center)
        place(edge.to, at, arrow(center, bus + 18 + caption(edge, center, bus) * 14))
      end

      def arrow(center, stem)
        @canvas.wire([Point.new(center, stem), Point.new(center, stem + 14)])
        stem + 14
      end

      def bus_line(box, bus, center)
        points = [box.foot, Point.new(box.center, bus), Point.new(center, bus), Point.new(center, bus + 8)]
        @canvas.raw(%(<path d="M #{points.join(" L ")}" class="wire"/>), bus + 8)
      end

      def caption(edge, center, bus)
        lines = Words.wrap(@reasons.of(edge), 34)
        lines.each_with_index { |line, row| @canvas.text(Point.new(center, bus + 22 + row * 14).middle, line, "k") }
        lines.size
      end

      def ending(box, stops)
        top = box.bottom + GAP
        @canvas.wire([box.foot, Point.new(box.center, top)])
        stops.reduce(top) { |at, stop| at + @plate.stack(box.left, at, Plate::WIDTH, stop) + 8 }
      end
    end
  end
end
