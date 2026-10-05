# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"
require_relative "lines"
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

      CRITERIA_HEADING = 'the done criteria are the bullets under its "## Done criteria" heading'

      def self.spec_line(context, spec)
        file = "#{context.intent.dir}/spec.md"
        return "spec: #{file}; #{CRITERIA_HEADING}" if spec.present?

        "spec: none yet; the agent writes #{file}, and #{CRITERIA_HEADING}"
      end

      NODE_AND_EDGE_COMMANDS = [
        Commands::NodeAdd, Commands::NodeRemove, Commands::NodeClaim, Commands::NodeRelease, Commands::NodeDone,
        Commands::NodeFail, Commands::NodePark, Commands::NodeAnswer, Commands::EdgeAdd, Commands::EdgeRemove
      ].freeze

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "print the goal and its criteria" do |context|
        spec = Graph::Knowledge::Spec.new(context.retrieval, context.intent_id)
        spec.goal_lines.then { |lines| lines.empty? ? [context.intent.title] : lines }.each { |line| context.print("goal: #{line}") }
        context.print(ShowBrief.spec_line(context, spec))
        spec.done_criteria.each { |criterion| context.print("criterion: #{criterion}") }
      end

      read "print the rulings" do |context|
        Lines.rulings(context.retrieval.rulings(context.intent_id)).each { |line| context.print(line) }
      end

      read "print the ready nodes" do |context|
        context.retrieval.ready_nodes(context.intent_id).each { |node| context.print(Lines.ready_node(node)) }
      end

      read "print the usage of the node and edge commands" do |context|
        NODE_AND_EDGE_COMMANDS.each { |klass| context.print(klass.usage_line) }
      end

      outcome :done, offers: "plastic graph ready %{intent_id}", because: "intent %{intent_id} is briefed"
    end
  end
end
