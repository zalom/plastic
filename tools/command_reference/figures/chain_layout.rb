# frozen_string_literal: true

module CommandReference
  module Figures
    # Where each workflow of a chain sits: one layer for each step away from the entry.
    class ChainLayout
      BOX_W = 180
      BOX_H = 56
      GAP = 24
      STEP = BOX_W + GAP
      RISE = 64

      def initialize(flows, edges, entry)
        @flows = flows
        @edges = edges
        @depth = { entry => 0 }
        @settled = false
      end

      def width = [layers.map(&:size).max.to_i * STEP + GAP, 480].max

      def frame(key) = place.fetch(key)

      def route(edge) = frame(edge.from).route_to(frame(edge.to), RISE / 2)

      private

      def place = @place ||= layers.each_with_index.flat_map { |keys, level| keys.zip(slots(keys.size, level)) }.to_h

      def slots(count, level)
        Array.new(count) { |index| Box.new(margin(count) + index * STEP, 16 + level * (BOX_H + RISE), BOX_W, BOX_H) }
      end

      def margin(count) = (width - (count * STEP - GAP)) / 2

      def layers
        @layers ||= @flows.map(&:key).group_by { |key| depth.fetch(key, 0) }.sort.map(&:last)
      end

      def depth
        @flows.each { |flow| deepen(flow.key) } unless @settled
        @settled = true
        @depth
      end

      def deepen(key)
        targets(key).each { |target| @depth[target] = [@depth.fetch(target, 0), @depth.fetch(key, 0) + 1].max }
      end

      def targets(key) = @edges.select { |edge| edge.from == key }.map(&:to)
    end
  end
end
