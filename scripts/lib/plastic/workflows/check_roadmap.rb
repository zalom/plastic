# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/roadmap_check"

module Plastic
  module Workflows
    # Prints each finding, or "no findings"; a finding fails the call.
    class CheckRoadmap < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :findings

      read "find problems" do |context|
        context[:findings] = Graph::RoadmapCheck.new(context.retrieval, context.slug).all
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
