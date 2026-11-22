# frozen_string_literal: true

require_relative "../../edge_walk"

module Plastic
  module Graph
    module Knowledge
      class Findings
        # A finding is its words and the command that repairs it, or nil when no command does.
        Finding = Data.define(:text, :repair)

        # The findings about the edges of one intent: a need on a removed node, and a loop that a hand-edited
        # graph.json can hold, though `edge add` refuses to write one.
        class EdgeFindings
          def initialize(intent_id, nodes, edges)
            @intent_id = intent_id
            @removed = nodes.select { |node| node.state == "removed" }.to_set(&:id)
            @live = nodes.reject { |node| node.state == "removed" }.to_set(&:id)
            @needs = edges.select { |edge| edge.kind == "needs" }
          end

          def all = removed_findings + loop_findings

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
