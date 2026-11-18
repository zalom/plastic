# frozen_string_literal: true

require_relative "spec"

module Plastic
  module Graph
    module Knowledge
      # The five checks `plastic graph check` runs on one intent's live nodes
      # (every node but a removed one) and its spec.
      class Findings
        def self.findings_finding(node)
          "node #{node.id} is done with no findings" if node.state == "done" && node.findings.to_s.strip.empty?
        end

        def self.retry_finding(node, runs)
          "node #{node.id} retried #{runs} times" if runs > 3 && node.answer.to_s.empty?
        end

        def initialize(retrieval, intent_id)
          @retrieval = retrieval
          @intent_id = intent_id
        end

        def all = node_findings + criterion_finding

        private

        def live = @live ||= @retrieval.structure.nodes(@intent_id).reject { |node| node.state == "removed" }

        def run_counts = @run_counts ||= @retrieval.structure.runs(@intent_id).group_by(&:node_id).transform_values(&:size).tap { |counts| counts.default = 0 }

        def edges = @edges ||= @retrieval.structure.edges(@intent_id)

        def node_findings = live.flat_map { |node| findings_for(node) }

        def findings_for(node) = [Findings.findings_finding(node), edge_finding(node), Findings.retry_finding(node, run_counts[node.id])].compact

        def edge_finding(node)
          return nil if live.size < 2 || touches?(node)

          "node #{node.id} has no edge"
        end

        def touches?(node) = edges.any? { |edge| edge.touches?(node.id) }

        def criterion_finding
          return [] unless Spec.new(@retrieval, @intent_id).done_criteria.empty?

          ["intent #{@intent_id} names no done criterion"]
        end
      end
    end
  end
end
