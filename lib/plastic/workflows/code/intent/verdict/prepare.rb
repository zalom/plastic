# frozen_string_literal: true

require_relative "../verdict"
require_relative "../../../../code_workflow"
require_relative "../../../../graph/knowledge/spec"
require_relative "../../../review_round"

module Plastic
  module Workflows
    module Code
      module Intent
        class Verdict
          # Reads the intent and its judge rounds before a verdict is written: a missing or closed intent fails, an accept with no done criterion, no node or a live node that is not done fails, both rounds used is the owner's step.
          class Prepare < CodeWorkflow
            sets :problem, :criterion_problem, :node_problem, :open_nodes

            read "check the intent" do |context|
              context[:problem] = context.work.open_intent_problem(context.intent_id, "verdict")
            end

            gate "%{problem}", stops: :failure, pass: ->(context) { context.problem.nil? }

            read "check the delivery behind an accept" do |context|
              accepting = context.verdict == "accept"
              nodes = accepting ? context.retrieval.nodes(context.intent_id).select(&:live?) : []
              context[:criterion_problem] = ("intent #{context.intent_id} names no done criterion" if accepting && no_criterion?(context))
              context[:node_problem] = ("intent #{context.intent_id} has no node" if accepting && nodes.empty?)
              context[:open_nodes] = nodes.reject { |node| node.state == "done" }.map(&:id).join(", ")
            end

            def self.no_criterion?(context) = Plastic::Graph::Knowledge::Spec.new(context.retrieval, context.intent_id).done_criteria.empty?

            gate "%{criterion_problem}; an accept needs one", stops: :failure, offers: "plastic intent spec %{intent_id}",
              because: "the spec needs a done criterion before an accept", pass: ->(context) { context.criterion_problem.nil? }
            gate "%{node_problem}; an accept needs the work done", stops: :failure, offers: "plastic node add %{intent_id} TITLE --criterion KEY",
              because: "an accept needs a node that is done", pass: ->(context) { context.node_problem.nil? }
            gate "intent %{intent_id} has nodes that are not done: %{open_nodes}", stops: :failure, offers: "plastic graph show %{intent_id}",
              because: "an accept needs every node done", pass: ->(context) { context.open_nodes.to_s.empty? }
            gate ReviewRound::MESSAGE, stops: :refusal,
              pass: ->(context) { context.work.rounds_left?(context.intent_id) }

            outcome :recording
          end
        end
      end
    end
  end
end
