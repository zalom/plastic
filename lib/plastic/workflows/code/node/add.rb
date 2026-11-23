# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/spec"

module Plastic
  module Workflows
    module Code
      module Node
        # Writes a new node, open and ready, unless the intent is done or
        # abandoned.
        class Add < CodeWorkflow
          clear_declarations

          sets :id, :input_problem, :found_problem, :found_refusal

          open_intent_gates "nodes"

          read "check the kind and the criterion" do |context|
            context[:input_problem] = kind_problem(context) || criterion_problem(context)
            context[:found_problem], context[:found_refusal] = found_in_problems(context)
          end

          gate "%{input_problem}", stops: :failure,
            words: "the kind is not orchestrator, work or retrieval, or the criterion key is not one of the spec",
            pass: ->(context) { context.input_problem.nil? }

          gate "%{found_problem}", stops: :failure,
            words: "the node the new work was found in is not a live node of the intent",
            pass: ->(context) { context.found_problem.nil? }

          gate "%{found_refusal}", stops: :refusal,
            words: "the node the new work was found in is removed",
            pass: ->(context) { context.found_refusal.nil? }

          step "add the node", done: ->(context) { !context.id.nil? },
            changes: { work: "The node is added to the work graph of the intent" } do |context|
            node = context.work.add_node(intent_id: context.intent_id, title: context.title, criterion: context.criterion,
              input: context.input, kind: context.kind || "work", found_in: context.found_in, deadline: context.deadline&.to_i)
            context[:id] = node.id
          end

          read "say what was added" do |context|
            context.print("node: #{context.id}")
          end

          def self.kind_problem(context)
            kind = context.kind
            return nil if kind.nil? || Plastic::Graph::Work::Node::KINDS.include?(kind)

            "kind #{kind.inspect} is not a node kind; the kinds are: #{Plastic::Graph::Work::Node::KINDS.join(", ")}"
          end

          # [the failure, the refusal]: a missing node fails, a removed node is refused, as `edge add` does.
          def self.found_in_problems(context)
            found_in = context.found_in
            return [nil, nil] if found_in.nil?

            intent_id = context.intent_id
            state = context.retrieval.node(intent_id, found_in)&.state
            return ["#{found_in} is not a node of intent #{intent_id}", nil] if state.nil?

            [nil, ("#{found_in} is removed" if state == "removed")]
          end

          def self.criterion_problem(context)
            intent_id = context.intent_id
            spec = Plastic::Graph::Knowledge::Spec.new(context.retrieval, intent_id)
            return "intent #{intent_id} has no synced spec.md; write its done criteria, then run plastic sync up" unless spec.present?

            key_problem(spec.criteria_by_key.keys, context.criterion)
          end

          def self.key_problem(keys, criterion)
            "criterion #{criterion.inspect} is not a done criterion key of spec.md; the keys are: #{keys.join(", ")}" unless keys.include?(criterion)
          end

          outcome :done, offers: "plastic edge add %{intent_id} FROM TO",
            because: "node %{id} is open; an edge FROM TO means TO reads, changes or tests what FROM makes; add the edges of the plan, then run plastic graph check %{intent_id}"
        end
      end
    end
  end
end
