# frozen_string_literal: true

require_relative "../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Node
        # Renews the claim of this agent of the session on a claimed node, and no other claim. A node another session
        # holds, one another agent of this session holds, or one nobody holds, refuses and changes nothing.
        class Renew < CodeWorkflow
          clear_declarations

          sets :node, :problem, :renewed, :holder

          read "find the node" do |context|
            node = context.retrieval.node(context.intent_id, context.id)
            context[:node] = node
            context[:problem] = problem_for(context, node)
          end

          def self.problem_for(context, node)
            return "no node #{context.id} in intent #{context.intent_id}" unless node
            return nil if node.held_by?(context.session)

            id = node.id
            state = node.state
            (state == "claimed") ? "node #{id} is held by session #{node.claimed_by}" : "node #{id} is #{state}; it holds no claim"
          end

          gate "%{problem}", stops: :refusal,
            words: "the node is not claimed by this session",
            pass: ->(context) { context.problem.nil? }

          step "renew the claim", done: ->(context) { !context.renewed.nil? },
            changes: { work: "The claim of this agent of the session on the node is renewed to now" } do |context|
            context[:renewed] = context.work.renew_node(intent_id: context.intent_id, id: context.id, by: context.session, agent: context.running_agent)
            context[:holder] = holder(context) unless context.renewed
          end

          # The agent of the session whose name is on the open run of the node.
          def self.holder(context)
            run = context.retrieval.structure.runs(context.intent_id).reverse.find { |candidate| candidate.node_id == context.id && candidate.open? }
            agent = run&.agent.to_s
            agent.empty? ? "session #{context.session} with no agent name" : "agent #{agent} of session #{context.session}"
          end

          gate "node %{id} is held by %{holder}", stops: :refusal,
            words: "another agent of this session holds the node",
            pass: ->(context) { context.renewed }

          read "say what was renewed" do |context|
            context.print("node: #{context.id} renewed")
          end

          outcome :done, offers: "plastic node done %{intent_id} %{id} TEXT", because: "node %{id} is claimed by this session"
        end
      end
    end
  end
end
