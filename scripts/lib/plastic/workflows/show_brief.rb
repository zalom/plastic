# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/spec"
require_relative "../commands/node_add"
require_relative "../commands/node_remove"
require_relative "../commands/node_claim"
require_relative "../commands/node_release"
require_relative "../commands/node_done"
require_relative "../commands/node_fail"
require_relative "../commands/node_park"
require_relative "../commands/node_answer"
require_relative "../commands/edge_add"
require_relative "../commands/edge_remove"

module Plastic
  module Workflows
    # Prints the goal, the done criteria, the rulings with superseded ones
    # marked, the ready nodes and the usage of the node and edge commands.
    class ShowBrief < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent

      NODE_AND_EDGE_COMMANDS = [
        Commands::NodeAdd, Commands::NodeRemove, Commands::NodeClaim, Commands::NodeRelease, Commands::NodeDone,
        Commands::NodeFail, Commands::NodePark, Commands::NodeAnswer, Commands::EdgeAdd, Commands::EdgeRemove
      ].freeze

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "print the goal and its criteria" do |context|
        context.print("goal: #{context.intent.title}")
        context.print("spec: #{context.intent.dir}/spec.md")
        Graph::Spec.new(context.retrieval, context.intent_id).done_criteria.each { |criterion| context.print("criterion: #{criterion}") }
      end

      read "print the rulings" do |context|
        rulings = context.retrieval.rulings(context.intent_id)
        superseded = rulings.filter_map(&:supersedes).to_set
        rulings.each { |ruling| context.print(ShowBrief.ruling_line(ruling, superseded)) }
      end

      def self.ruling_line(ruling, superseded)
        id = ruling.id
        mark = superseded.include?(id) ? " (superseded)" : ""
        "ruling: #{id} #{ruling.text}#{mark}"
      end

      read "print the ready nodes" do |context|
        context.retrieval.ready_nodes(context.intent_id).each { |node| context.print("ready: #{node.id} #{node.title}") }
      end

      read "print the usage of the node and edge commands" do |context|
        NODE_AND_EDGE_COMMANDS.each { |klass| context.print(klass.usage_line) }
      end

      outcome :done, offers: "plastic graph ready %{intent_id}", because: "intent %{intent_id} is briefed"
    end
  end
end
