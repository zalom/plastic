# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Node
        # Renews the claim of this session on a claimed node. A node another session holds, or
        # one nobody holds, refuses and changes nothing.
        class Renew < CodeWorkflow
          clear_declarations

          sets :node, :problem, :renewed

          read "find the node" do |context|
            node = context.retrieval.node(context.intent_id, context.id)
            context[:node] = node
            context[:problem] = problem_for(context, node)
          end

          def self.problem_for(context, node)
            return "no node #{context.id} in intent #{context.intent_id}" unless node
            return nil if node.held_by?(context.session)

            (node.state == "claimed") ? "node #{node.id} is held by session #{node.claimed_by}" : "node #{node.id} is #{node.state}; it holds no claim"
          end

          gate "%{problem}", stops: :refusal,
            words: "the node is not claimed by this session",
            pass: ->(context) { context.problem.nil? }

          step "renew the claim", done: ->(context) { context.renewed == true },
            changes: { work: "The claim of this session on the node is renewed to now" } do |context|
            context.work.renew_claims(context.session)
            context[:renewed] = true
          end

          read "say what was renewed" do |context|
            context.print("node: #{context.id} renewed")
          end

          outcome :done, offers: "plastic node done %{intent_id} %{id} TEXT", because: "node %{id} is claimed by this session"
        end
      end
    end
  end
end
