# frozen_string_literal: true

module Plastic
  module Graph
    # The checks `plastic roadmap check` runs on one roadmap's rows: a loop
    # over its edges, an edge to an item not on the roadmap, and an item
    # whose intent_id names no intent.
    class RoadmapCheck
      def initialize(retrieval, slug)
        @retrieval = retrieval
        @slug = slug
      end

      def all = dangling_findings + loop_findings + missing_intent_findings

      private

      def items = @items ||= @retrieval.roadmap_items(@slug)

      def edges = @edges ||= @retrieval.roadmap_edges(@slug)

      def item_ids = @item_ids ||= items.map(&:item)

      def dangling_findings
        edges.reject { |edge| item_ids.include?(edge.from) && item_ids.include?(edge.to) }
          .map { |edge| "edge #{edge.from} to #{edge.to} names an item not on roadmap #{@slug}" }
      end

      def loop_findings
        items.select { |item| loop?(item.item, item.item, []) }.map { |item| "item #{item.item} loops back to itself" }
      end

      def loop?(start, item, seen)
        return false if seen.include?(item)

        successors(item).any? { |next_item| next_item == start || loop?(start, next_item, seen + [item]) }
      end

      def successors(item) = edges.select { |edge| edge.from == item }.map(&:to)

      def missing_intent_findings
        items.select { |item| item.intent_id && !@retrieval.intent(item.intent_id) }
          .map { |item| "item #{item.item} names no intent #{item.intent_id}" }
      end
    end
  end
end
