# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # One shared shape for every workflow that moves a node through a
    # single state change: run the move, gate on its refusal, print the
    # result, and offer what comes next. MOVES holds what differs between
    # moves, and a subclass calls `move` once with its key. A refused move
    # keeps its run open, so the next call moves again.
    class MoveNode < CodeWorkflow
      MOVES = {
        release_node: { state: "open", step: "release the node", say: "say what was released", fields: [],
                        offers: "plastic node claim %{intent_id} %{id}" },
        done_node: { state: "done", step: "finish the node", say: "say what was done", fields: { findings: :text },
                     offers: "plastic graph ready %{intent_id}" },
        fail_node: { state: "failed", step: "fail the node", say: "say what failed", fields: { reason: :text },
                     offers: "plastic node release %{intent_id} %{id}" },
        ask_node: { state: "needs_info", step: "ask the owner", say: "say what was asked", fields: { question: :text },
                    offers: "plastic node resolve %{intent_id} %{id} TEXT" },
        impede_node: { state: "impeded", step: "record the impediment", say: "say what impedes the node", fields: { reason: :text },
                       offers: "plastic node resolve %{intent_id} %{id} TEXT" },
        resolve_node: { state: "open", step: "resolve the node", say: "say what was resolved", fields: { answer: :text },
                        offers: "plastic node claim %{intent_id} %{id}" },
        remove_node: { state: "removed", step: "remove the node", say: "say what was removed", fields: %i[reason],
                       offers: "plastic graph ready %{intent_id}" }
      }.freeze

      RESULT_VERBS = %i[done_node fail_node ask_node impede_node].freeze

      CHANGES = {
        release_node: "The node is released and open again",
        done_node: "The node is marked done with its findings",
        fail_node: "The node is marked failed with the reason",
        ask_node: "The node waits for the owner's answer to the question",
        impede_node: "The node is marked impeded with the reason",
        resolve_node: "The node is resolved with the answer and open again",
        remove_node: "The node is removed from the work graph with the reason"
      }.freeze

      def self.move(verb)
        shape = MOVES.fetch(verb)
        sets :intent, :problem, :moved, :taken
        intent_steps
        move_steps(verb, shape)
        result_steps(shape)
      end

      def self.intent_steps
        read("find the intent") { |context| context[:intent] = context.retrieval.intent(context.intent_id) }
        gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { context.intent }
      end

      def self.move_steps(verb, shape)
        read("forget a refusal of an earlier call") { |context| forget_refusal(context) }
        step(shape.fetch(:step), done: method(:tried?), changes: { work: CHANGES.fetch(verb) }) { |context| run_move(context, verb, shape) }
        gate "%{problem}", stops: :refusal,
          words: "another session took the claim of the node after it lapsed",
          pass: ->(context) { !context.taken }
        gate "%{problem}", stops: :failure,
          words: "the node is not in the intent, or its state does not allow this move",
          pass: method(:moved?)
      end

      def self.forget_refusal(context)
        context[:moved] = nil if context.moved == false
      end

      def self.tried?(context) = [true, false].include?(context.moved)

      def self.moved?(context) = context.moved == true

      def self.result_steps(shape)
        state = shape.fetch(:state)
        read(shape.fetch(:say)) { |context| context.print("node: #{context.id} #{state}") }
        outcome :done, offers: shape.fetch(:offers), because: "node %{id} is #{state}"
      end

      def self.run_move(context, verb, shape)
        node = context.work.public_send(verb, intent_id: context.intent_id, id: context.id, by: context.session, **fields(context, shape), **files(context, verb))
        settle(context, node || (verb == :done_node && repeated_done?(context)), shape.fetch(:state))
      end

      def self.settle(context, moved, state)
        context[:problem] = moved ? nil : refusal(context, state)
        context[:taken] = !moved && taken?(context)
        context[:moved] = !context.problem
      end

      def self.fields(context, shape) = shape.fetch(:fields).to_h { |name, source| [name, context.public_send(source || name)] }

      def self.files(context, verb) = RESULT_VERBS.include?(verb) ? { files: context.files } : {}

      def self.taken?(context)
        node = context.retrieval.node(context.intent_id, context.id)
        session = context.session
        return false if node.nil? || session.nil?

        held_by_other?(node, session) || finished_by_other?(context, node)
      end

      def self.held_by_other?(node, session) = node.state == "claimed" && node.claimed_by != session

      def self.finished_by_other?(context, node)
        finisher = finisher_of(context, node)
        node.state == "done" && !finisher.nil? && finisher != context.session
      end

      # The session of the last run of a node: the one that finished it when the node is done.
      def self.finisher_of(context, node)
        runs = context.retrieval.structure.runs(node.intent_id).select { |run| run.node_id == node.id }
        runs.max_by(&:number)&.session_id
      end

      # The holder that finished the node asks again: nothing moves and nothing is written.
      def self.repeated_done?(context)
        node = context.retrieval.node(context.intent_id, context.id)
        !node.nil? && node.state == "done" && finisher_of(context, node) == context.session
      end

      def self.refusal(context, state)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        return "no node #{id} in intent #{intent_id}" unless node

        taken?(context) ? "node #{id} is held by session #{node.claimed_by || finisher_of(context, node)}; its claim was taken" : node.refusal(state)
      end
    end
  end
end
