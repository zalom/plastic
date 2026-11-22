# frozen_string_literal: true

module Plastic
  module Graph
    # Walks the edges of one graph from a node, with a stack and a visited set, so a chain of any length ends. It
    # takes the edges as [from, to] pairs and decides what a node reaches, which a work graph and a roadmap share.
    class EdgeWalk
      def initialize(pairs)
        @successors = pairs.each_with_object(Hash.new { |hash, key| hash[key] = [] }) { |(from, to), index| index[from] << to }
      end

      # The nodes from `from` to `to` along the edges, both ends included, or nil when `to` is not reached.
      def path(from, to)
        return [from] if from == to

        trail(from, to)
      end

      # The nodes from `start` back to `start` along at least one edge, or nil when `start` is on no cycle.
      def cycle(start)
        back = trail(start, start)
        back && [start, *back.drop(1)]
      end

      private

      # The path from `from` to `to` over one or more edges.
      def trail(from, to)
        parents = {}
        stack = [from]
        until stack.empty?
          fresh = unseen(stack.pop, parents)
          return route(parents, from, to) if fresh.include?(to)

          stack.concat(fresh)
        end
        nil
      end

      # The successors of `node` not seen yet, each marked with `node` as the one it came from.
      def unseen(node, parents)
        @successors.fetch(node, []).reject { |successor| parents.key?(successor) }.each { |successor| parents[successor] = node }
      end

      def route(parents, from, to)
        nodes = [to]
        nodes.unshift(parents.fetch(nodes.first)) until nodes.first == from && nodes.size > 1
        nodes
      end
    end
  end
end
