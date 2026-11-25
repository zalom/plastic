# frozen_string_literal: true

module Plastic
  module Graph
    class EdgeWalk
      # Finds every node that lies on a cycle in one pass over the edges: the strongly connected parts of the graph,
      # numbered with an explicit stack of open nodes so a chain of any length ends.
      class Cyclic
        def initialize(successors)
          @successors = successors
          @number = {}
          @low = {}
          @held = []
          @open = {}
          @found = Set.new
        end

        def call
          @successors.each_key { |root| descend(root) unless @number.key?(root) }
          @found
        end

        private

        def descend(root)
          frames = [enter(root)]
          until frames.empty?
            node, pending = frames.last
            successor = pending.shift
            successor ? step(frames, node, successor) : leave(frames)
          end
        end

        def step(frames, node, successor)
          return frames.push(enter(successor)) unless @number.key?(successor)

          @low[node] = [@low[node], @number[successor]].min if @open.key?(successor)
        end

        def enter(node)
          @number[node] = @low[node] = @number.size
          @held.push(node)
          @open[node] = true
          [node, @successors.fetch(node, []).dup]
        end

        def leave(frames)
          node, = frames.pop
          release(node) if @low[node] == @number[node]
          parent = frames.last&.first
          @low[parent] = [@low[parent], @low[node]].min if parent
        end

        def release(root)
          members = [@held.pop]
          members.push(@held.pop) until members.last == root
          members.each { |member| @open.delete(member) }
          @found.merge(members) if members.size > 1 || @successors.fetch(root, []).include?(root)
        end
      end
    end
  end
end
