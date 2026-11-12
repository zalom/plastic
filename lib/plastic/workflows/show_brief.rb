# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"
require_relative "../graph/work/main_session"
require_relative "lines"
require_relative "../commands/node/add"
require_relative "../commands/node/remove"
require_relative "../commands/node/claim"
require_relative "../commands/node/release"
require_relative "../commands/node/done"
require_relative "../commands/node/fail"
require_relative "../commands/node/ask"
require_relative "../commands/node/impede"
require_relative "../commands/node/resolve"
require_relative "../commands/edge/add"
require_relative "../commands/edge/remove"

module Plastic
  module Workflows
    # Prints the goal, the done criteria, the rulings with superseded ones
    # marked, the ready nodes, the main session steps and the usage of the node
    # and edge commands.
    class ShowBrief < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent

      def self.spec_line(context, spec)
        file = "#{context.intent.dir}/spec.md"
        return "spec: #{file}; #{Lines::CRITERIA}" if spec.present?

        "spec: none yet; the agent writes #{file}, and #{Lines::CRITERIA}"
      end

      NODE_AND_EDGE_COMMANDS = [
        Commands::Node::Add, Commands::Node::Remove, Commands::Node::Claim, Commands::Node::Release, Commands::Node::Done,
        Commands::Node::Fail, Commands::Node::Ask, Commands::Node::Impede, Commands::Node::Resolve, Commands::Edge::Add, Commands::Edge::Remove
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

      read "print the main session steps" do |context|
        Graph::Work::MainSession.lines(context.intent_id).each { |line| context.print(line) }
      end

      read "print the usage of the node and edge commands" do |context|
        NODE_AND_EDGE_COMMANDS.each { |klass| context.print(klass.usage_line) }
      end

      outcome :done, offers: "plastic graph ready %{intent_id}", because: "intent %{intent_id} is briefed"
    end
  end
end
