# frozen_string_literal: true

module CommandReference
  module Figures
    # Puts the cards of a call's workflows on a canvas, each below the one it follows.
    class Placement
      GAP = 26

      def initialize(tree, reasons, canvas)
        @tree = tree
        @reasons = reasons
        @canvas = canvas
        @plate = Plate.new(canvas)
      end

      def paint = place(@tree.entry, @tree.entry_left, 56)

      private

      def place(key, left, top)
        flow = @tree.flow(key)
        box = flow_card(flow, left, top)
        below = Sides.new(@canvas, @plate, box, @tree.beside(key)).draw
        @tree.onward?(key) ? branch(box, left, key, below) : ending(box, FlowStops.new(flow).closing)
      end

      def flow_card(flow, left, top)
        card = Card.at(left + @tree.span(flow.key) / 2 - Plate::WIDTH / 2, top, Plate::WIDTH, Plate.lines(flow.klass.summary))
        card.box.tap { @plate.flow(card, flow) }
      end

      def branch(box, left, key, below)
        bus = below + 22
        start = left + (@tree.span(key) - @tree.children_span(key)) / 2
        @tree.onward(key).reduce(start) do |at, edge|
          descend(box, bus, edge, at)
          at + @tree.span(edge.to)
        end
      end

      def descend(box, bus, edge, at)
        target = edge.to
        center = at + @tree.span(target) / 2
        @canvas.line(box.branch_to(center, bus))
        place(target, at, arrow(center, bus + 18 + caption(edge, center, bus) * 14))
      end

      def arrow(center, stem)
        tail = Point.new(center, stem)
        tip = tail.shift(0, 14)
        @canvas.wire([tail, tip])
        tip.top
      end

      def caption(edge, center, bus)
        lines = Words.wrap(@reasons.of(edge), 34)
        lines.each_with_index { |line, row| @canvas.text(Point.new(center, bus + 22 + row * 14).middle, line, "k") }
        lines.size
      end

      def ending(box, stops)
        route = box.drop(GAP)
        @canvas.wire(route)
        stops.reduce(route.last.top) { |at, stop| at + @plate.stack(box.left, at, Plate::WIDTH, stop) + 8 }
      end
    end
  end
end
