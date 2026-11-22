# frozen_string_literal: true

require_relative "../../edge_walk"

module Plastic
  module Graph
    module Knowledge
      class Findings
        # A finding is its words, the command that repairs it, and the hand edit that repairs it when no command does.
        # Either is nil when it does not apply.
        Finding = Data.define(:text, :repair, :hand) do
          def initialize(text:, repair:, hand: nil) = super
        end

        # The findings about the edges of one intent: a need on a removed node, and a loop that a hand-edited
        # graph.json can hold, though `edge add` refuses to write one.
        class EdgeFindings
          def initialize(intent_id, nodes, edges)
            @intent_id = intent_id
            @removed = nodes.select { |node| node.state == "removed" }.to_set(&:id)
            @live = nodes.reject { |node| node.state == "removed" }.to_set(&:id)
            @needs = edges.select { |edge| edge.kind == "needs" }
            @edge_count = edges.size
          end

          def all = removed_findings + loop_findings

          # A graph of several live nodes with no edge at all: the planner likely forgot the edges. It stops nothing.
          def unlinked
            return [] if @live.size < 2 || @edge_count.positive?

            [Finding.new("the graph has #{@live.size} nodes and no edge at all", "plastic edge add #{@intent_id} FROM TO")]
          end

          private

          def removed_findings
            @needs.select { |edge| @removed.include?(edge.from) && @live.include?(edge.to) }.map do |edge|
              Finding.new("node #{edge.to} needs #{edge.from}, which is removed", "plastic edge remove #{@intent_id} #{edge.from} #{edge.to}")
            end
          end

          def loop_findings
            walk = EdgeWalk.new(@needs.map { |edge| [edge.from, edge.to] })
            covered = Set.new
            walk.cyclic.sort.filter_map do |name|
              next if covered.include?(name)

              walk.cycle(name).tap { |path| covered.merge(path) }.then { |path| loop_finding(path) }
            end
          end

          def loop_finding(path)
            Finding.new("nodes loop: #{path.join(" -> ")}", "plastic edge remove #{@intent_id} #{path[-2]} #{path[-1]}")
          end
        end
      end
    end
  end
end
