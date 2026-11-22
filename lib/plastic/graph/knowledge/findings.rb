# frozen_string_literal: true

require_relative "spec"
require_relative "../work/stored_output"
require_relative "findings/edge_findings"
require_relative "findings/schema_findings"

module Plastic
  module Graph
    module Knowledge
      # The checks `plastic graph check` runs on one intent's live nodes
      # (every node but a removed one), its edges and its spec. Each finding carries the command that repairs it.
      class Findings
        def self.findings_finding(node)
          "node #{node.id} is done with no findings" if node.state == "done" && node.findings.to_s.strip.empty?
        end

        def self.retry_finding(node, runs)
          "node #{node.id} retried #{runs} times" if runs > 3 && node.answer.to_s.empty?
        end

        # `schemas` is the intent's Work::Schemas, or nil when the check has no folder to read.
        def initialize(retrieval, intent_id, schemas: nil)
          @retrieval = retrieval
          @intent_id = intent_id
          @schemas = schemas
        end

        def all = with_repairs.map(&:text)

        # The findings, each with the command that repairs it (nil when no command does).
        def with_repairs = node_findings + EdgeFindings.new(@intent_id, nodes, edges).all + criterion_finding + schema_findings

        private

        def nodes = @nodes ||= @retrieval.structure.nodes(@intent_id)

        def live = @live ||= nodes.reject { |node| node.state == "removed" }

        def run_counts = @run_counts ||= @retrieval.structure.runs(@intent_id).group_by(&:node_id).transform_values(&:size).tap { |counts| counts.default = 0 }

        def edges = @edges ||= @retrieval.structure.edges(@intent_id)

        def node_findings = live.flat_map { |node| findings_for(node) }

        def findings_for(node) = [findings_finding(node), output_finding(node), edge_finding(node), retry_finding(node)].compact

        def findings_finding(node) = Findings.findings_finding(node)&.then { |text| Finding.new(text, nil) }

        def output_finding(node)
          return nil if Work::StoredOutput.valid?(node.output)

          Finding.new("node #{node.id} holds output that is not JSON", nil)
        end

        def retry_finding(node)
          Findings.retry_finding(node, run_counts[node.id])&.then { |text| Finding.new(text, "plastic node resolve #{@intent_id} #{node.id} TEXT") }
        end

        def edge_finding(node)
          return nil if live.size < 2 || touches?(node)

          Finding.new("node #{node.id} has no edge", "plastic edge add #{@intent_id} #{node.id} TO")
        end

        def touches?(node) = edges.any? { |edge| edge.touches?(node.id) }

        def schema_findings = SchemaFindings.new(@intent_id, live.map(&:id), @schemas).all

        def criterion_finding
          return [] unless Spec.new(@retrieval, @intent_id).done_criteria.empty?

          [Finding.new("intent #{@intent_id} names no done criterion", "plastic intent spec #{@intent_id}")]
        end
      end
    end
  end
end
