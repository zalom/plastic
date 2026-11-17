# frozen_string_literal: true

module CommandReference
  module Figures
    # The shape of one call's workflows: which workflow follows which, and how wide each one's branch is.
    class Tree
      extend Forwardable

      COLUMN = 266
      MARGIN = 24
      SIDED = Plate::WIDTH + 2 * (Sides::GAP + Sides::WIDTH)

      def_delegators :@page, :entry, :words

      def initialize(page)
        @page = page
        @flows = page.flows.to_h { |flow| [flow.key, flow] }
        @onward = onward_of(page.edges)
        @spans = {}
      end

      def flow(key) = @flows.fetch(key)

      def onward?(key) = @onward.key?(key)

      def onward(key) = @onward.fetch(key)

      def width = [834, span(entry) + 2 * MARGIN].max

      def entry_left = (width - span(entry)) / 2

      def span(key) = @spans[key] ||= [children_span(key), beside(key).any? ? SIDED : COLUMN].max

      def children_span(key) = @onward.fetch(key, []).sum { |edge| span(edge.to) }

      def beside(key)
        stops = FlowStops.new(flow(key))
        Sides::Beside.new(stops.gates, onward?(key) ? stops.closing : [])
      end

      private

      def onward_of(edges)
        ranks = @flows.keys.each_with_index.to_h
        by_rank = ->(edge) { ranks.fetch(edge.to) }
        edges.group_by(&:from).transform_values { |each| each.sort_by(&by_rank) }
      end
    end
  end
end
