# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/spec"
require_relative "../../../graph/work/main_session"
require_relative "../../lines"

module Plastic
  module Workflows
    module Code
      module Intent
        # Prints the goal, the done criteria, the rulings with superseded ones
        # marked, the ready nodes, the main session steps and the usage of the node
        # and edge commands.
        class Brief < CodeWorkflow
          clear_declarations
          summary "Prints the goal, the done criteria, the rulings and the ready nodes of the intent."

          sets :intent

          def self.spec_line(context, spec)
            file = "#{context.intent.dir}/spec.md"
            return "spec: #{file}; #{Lines::CRITERIA}" if spec.present?

            "spec: none yet; the agent writes it with plastic intent spec #{context.intent_id} --from FILE, and #{Lines::CRITERIA}"
          end

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

          read "print the goal and its criteria" do |context|
            spec = Plastic::Graph::Knowledge::Spec.new(context.retrieval, context.intent_id)
            spec.goal_lines.then { |lines| lines.empty? ? [context.intent.title] : lines }.each { |line| context.print("goal: #{line}") }
            context.print(Brief.spec_line(context, spec))
            spec.done_criteria.each { |criterion| context.print("criterion: #{criterion}") }
          end

          read "print the rulings" do |context|
            Lines.rulings(context.retrieval.rulings(context.intent_id)).each { |line| context.print(line) }
          end

          read "print the ready nodes" do |context|
            context.retrieval.ready_nodes(context.intent_id).each { |node| context.print(Lines.ready_node(node)) }
          end

          read "print the main session steps" do |context|
            Plastic::Graph::Work::MainSession.lines(context.intent_id).each { |line| context.print(line) }
          end

          read "print the usage of the node and edge commands" do |context|
            context.command_usages.each { |line| context.print(line) }
          end

          outcome :done, offers: "plastic graph ready %{intent_id}", because: "intent %{intent_id} is briefed"
        end
      end
    end
  end
end
