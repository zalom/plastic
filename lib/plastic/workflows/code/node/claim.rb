# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../auto"

module Plastic
  module Workflows
    module Code
      module Node
        # Claims an open node whose needed nodes are done, once the owner gave the go-ahead. The fourth run of a
        # node moves it to needs_info instead, with the owner's question, and refuses. A node another
        # session holds, its claim renewed within 15 minutes, refuses and names the holder. A refused
        # claim keeps its command run open, so the next call claims again.
        class Claim < CodeWorkflow
          clear_declarations

          STOPPED = %w[refused capped blocked held].freeze

          sets :intent, :result, :node, :problem, :approval_problem

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
          gate "node claim names no session; set PLASTIC_SESSION", stops: :failure, pass: ->(context) { !context.session.nil? }

          read "check the go-ahead" do |context|
            context[:approval_problem] = Auto.approval_problem(context.intent_id, context)
          end

          gate "%{approval_problem}", stops: :refusal,
            words: "the intent has no go-ahead",
            pass: ->(context) { context.approval_problem.nil? }

          read "forget a refusal of an earlier call" do |context|
            context[:result] = nil if STOPPED.include?(context.result.to_s)
          end

          step "claim the node", done: ->(context) { !context.result.nil? },
            changes: { work: ["The node is claimed by this session", "A node with three runs moves to needing information, with the question for the owner"] } do |context|
            result, node = context.work.claim_node(intent_id: context.intent_id, id: context.id, by: context.session, agent: context.agent.to_s)
            context[:result] = result
            context[:node] = node
            context[:problem] = problem_for(context, node)
          end

          def self.problem_for(context, node)
            intent_id, id = context.intent_id, context.id
            case context.result
            when :refused then node ? node.refusal("claimed") : "no node #{id} in intent #{intent_id}"
            when :held then "node #{id} is held by session #{node.claimed_by}; its claim lapses 15 minutes after its last renewal"
            when :capped then "node #{id} claimed 3 times; the owner decides"
            when :blocked then "node #{id} needs a node that is not done; plastic graph ready #{intent_id} lists the nodes to claim"
            end
          end

          gate "%{problem}", stops: :refusal,
            words: "the node ran three times and the owner decides, or another session holds it",
            pass: ->(context) { !%w[capped held].include?(context.result.to_s) }
          gate "%{problem}", stops: :failure,
            words: "the node is not in the intent, is not open, or needs a node that is not done",
            pass: ->(context) { !STOPPED.include?(context.result.to_s) }

          read "print the brief" do |context|
            node = context.node
            context.print("node: #{node.id} #{node.title}")
            context.print("criterion: #{node.criterion}")
            context.print("input: #{node.input}") if node.input
            context.print("last reason: #{node.reason}") if node.reason
          end

          outcome :done, offers: "plastic node done %{intent_id} %{id} TEXT",
            because: "node %{id} is claimed"
        end
      end
    end
  end
end
