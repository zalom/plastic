# frozen_string_literal: true

require_relative "spec"

module Plastic
  module Graph
    module Knowledge
      # The five checks `plastic graph check` runs on one intent's live nodes
      # (every node but a removed one) and its spec.
      class Findings
        def self.judge_finding(node)
          "node #{node.id} is done with no judge" if node.state == "done" && !node.judge
        end

        def self.tests_finding(node)
          return nil unless node.state == "done" && node.judge == "tests"

          "node #{node.id} judged by tests with no findings" if node.findings.to_s.strip.empty?
        end

        def self.retry_finding(node)
          retries = node.retries
          "node #{node.id} retried #{retries} times" if retries > 3
        end

        def initialize(retrieval, intent_id)
          @retrieval = retrieval
          @intent_id = intent_id
        end

        def all = node_findings + criterion_finding

        private

        def live = @live ||= @retrieval.nodes(@intent_id).reject { |node| node.state == "removed" }

        def edges = @edges ||= @retrieval.edges(@intent_id)

        def node_findings = live.flat_map { |node| findings_for(node) }

        def findings_for(node) = [Findings.judge_finding(node), Findings.tests_finding(node), edge_finding(node), Findings.retry_finding(node)].compact

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
