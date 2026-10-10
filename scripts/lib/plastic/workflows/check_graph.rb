# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/findings"

module Plastic
  module Workflows
    # Prints each finding, or "no findings"; a finding fails the call.
    class CheckGraph < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :findings, :first

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "find problems" do |context|
        context[:findings] = Graph::Knowledge::Findings.new(context.retrieval, context.intent_id).all
        print_findings(context)
      end

      def self.print_findings(context)
        findings = context.findings
        return context.print("no findings") if findings.empty?

        findings.each { |finding| context.print("finding: #{finding}") }
      end

      gate "see the findings above", stops: :failure, pass: ->(context) { context.findings.empty? }

      read "find the first ready node" do |context|
        context[:first] = context.retrieval.ready_nodes(context.intent_id).first&.id
      end

      outcome :nothing, if: ->(context) { context.first.nil? }, offers: nil, because: "no node is ready to claim"
      outcome :done, offers: "plastic node claim %{intent_id} %{first}", because: "node %{first} is ready"
    end
  end
end
