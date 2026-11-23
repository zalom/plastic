# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/store_folder"
require_relative "../../../graph/work/packet"
require_relative "../../../graph/work/schemas"
require_relative "../../../graph/work/start_check"

module Plastic
  module Workflows
    module Code
      module Node
        # Claims an open node whose needed nodes are done, once the intent is in progress and the owner gave the
        # go-ahead. A done or abandoned intent fails and offers plastic next. The fourth run of a node moves it
        # to needs_info instead, with the owner's question, and refuses. A node another session holds, its claim
        # renewed within 15 minutes, refuses and names the holder. A refused claim keeps its command run open,
        # so the next call claims again.
        class Claim < CodeWorkflow
          clear_declarations

          STOPPED = %w[refused capped blocked held].freeze

          sets :intent, :status, :result, :node, :problem, :approval_problem, :output_problem, :start_check, :graph_problem

          read "find the intent" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:status] = context.intent&.status
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
          gate "node claim names no session; set PLASTIC_SESSION", stops: :failure, pass: ->(context) { !context.session.nil? }
          gate "intent %{intent_id} is %{status}", stops: :refusal, offers: "plastic next",
            because: "a node of a closed intent is never claimed; pick other work",
            pass: ->(context) { !context.intent.closed? }
          gate "intent %{intent_id} is %{status}; start it with plastic intent start %{intent_id}, or with plastic intent auto %{intent_id} for agent delivery",
            stops: :refusal, offers: "plastic intent start %{intent_id}", because: "a node is claimed only in an intent in progress",
            pass: ->(context) { context.status == "in_progress" }

          read "check the go-ahead" do |context|
            context[:approval_problem] = approval_problem(context.intent_id, context)
          end

          # The refusal a claim gives before the owner's go-ahead.
          def self.approval_problem(id, context)
            return nil if context.retrieval.structure.approval(id)

            "intent #{id} has no go-ahead; the owner approves it with plastic intent approve #{id}"
          end

          gate "%{approval_problem}", stops: :refusal,
            words: "the intent has no go-ahead",
            pass: ->(context) { context.approval_problem.nil? }

          read "check the graph before the first claim" do |context|
            context[:start_check] = Plastic::Graph::Work::StartCheck.new(context.retrieval, context.intent, context.scope.root)
            context[:graph_problem] = context.start_check.problem
          end

          gate "%{graph_problem}", stops: :refusal, offers: "plastic graph check %{intent_id}",
            because: "a loop or a need on a removed node stops the first claim; repair it, then claim again",
            words: "the graph holds a loop or a need on a removed node, and no node was claimed yet",
            pass: ->(context) { context.graph_problem.nil? }

          read "check the output of the needed nodes" do |context|
            node = context.retrieval.node(context.intent_id, context.id)
            context[:output_problem] = node && Plastic::Graph::Work::Packet.output_problem(context.retrieval, node)
          end

          gate "%{output_problem}", stops: :failure, offers: "plastic graph check %{intent_id}",
            because: "a needed node holds output that is not JSON, so no packet can be built; nothing was claimed",
            words: "a needed node holds output that is not JSON",
            pass: ->(context) { context.output_problem.nil? }

          read "forget a refusal of an earlier call" do |context|
            context[:result] = nil if STOPPED.include?(context.result.to_s)
          end

          step "claim the node", done: ->(context) { !context.result.nil? },
            changes: { work: ["The node is claimed by this session: PLASTIC_SESSION, else the harness session, else terminal- and the login at a terminal", "A node with three runs moves to needing information, with the question for the owner"] } do |context|
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
            words: "the node is not in the intent",
            pass: ->(context) { !(context.result == :refused && context.node.nil?) }
          gate "%{problem}", stops: :refusal,
            words: "the node is not open, or needs a node that is not done",
            pass: ->(context) { !STOPPED.include?(context.result.to_s) }

          read "print the brief" do |context|
            node = context.node
            context.print("node: #{node.id} #{node.title}")
            context.start_check.claim_lines.each { |line| context.print(line) }
            packet = packet_for(context, node)
            context.print("criterion: #{node.criterion}")
            context.print(packet.criterion_line)
            context.print("input: #{node.input}") if node.input
            context.print("last reason: #{node.reason}") if node.reason
            packet.answer_lines.each { |line| context.print(line) }
            context.data("packet", packet.to_h)
          end

          def self.packet_for(context, node)
            folder = Plastic::Graph::Knowledge::StoreFolder.new(context.scope.root)
            Plastic::Graph::Work::Packet.new(context.retrieval, node, schemas: Plastic::Graph::Work::Schemas.new(folder, context.intent.dir))
          end

          outcome :done, offers: "plastic node done %{intent_id} %{id} TEXT",
            because: "node %{id} is claimed"
        end
      end
    end
  end
end
