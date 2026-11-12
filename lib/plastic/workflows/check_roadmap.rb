# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/roadmap/check"

module Plastic
  module Workflows
    # Prints each finding, or "no findings"; a finding fails the call.
    class CheckRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :findings

      gate "no roadmap %{slug}", stops: :failure, pass: ->(context) { !context.retrieval.roadmap(context.slug).nil? }

      read "find problems" do |context|
        context[:findings] = Graph::Knowledge::Roadmap::Check.new(context.retrieval, context.slug).all
        print_findings(context)
      end

      def self.print_findings(context)
        findings = context.findings
        return context.print("no findings") if findings.empty?

        findings.each { |finding| context.print("finding: #{finding}") }
      end

      gate "see the findings above", stops: :failure, pass: ->(context) { context.findings.empty? }

      outcome :done, offers: "plastic roadmap show %{slug}", because: "roadmap %{slug} has no findings"
    end
  end
end
