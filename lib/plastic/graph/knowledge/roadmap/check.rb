# frozen_string_literal: true

require_relative "../../edge_walk"
require_relative "../roadmap"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # The checks `plastic roadmap check` runs on one roadmap's rows: a loop
        # over its edges, an edge to an item not on the roadmap, and an item
        # whose intent_id names no intent.
        class Check
          def initialize(retrieval, slug)
            @retrieval = retrieval
            @slug = slug
          end

          def all = dangling_findings + loop_findings + missing_intent_findings

          private

          def items = @items ||= @retrieval.roadmaps.items(@slug)

          def edges = @edges ||= @retrieval.roadmaps.edges(@slug)

          def item_ids = @item_ids ||= items.map(&:item)

          def dangling_findings
            edges.map { |edge| [edge.from, edge.to] }
              .reject { |ends| (ends - item_ids).empty? }
              .map { |from, to| "edge #{from} to #{to} names an item not on roadmap #{@slug}" }
          end

          def loop_findings
            looped = EdgeWalk.new(edges.map { |edge| [edge.from, edge.to] }).cyclic
            item_ids.select { |name| looped.include?(name) }.map { |name| "item #{name} loops back to itself" }
          end

          def missing_intent_findings
            items.map { |item| [item.item, item.intent_id] }
              .select { |_name, intent_id| intent_id && !@retrieval.intent(intent_id) }
              .map { |name, intent_id| "item #{name} names no intent #{intent_id}" }
          end
        end
      end
    end
  end
end
