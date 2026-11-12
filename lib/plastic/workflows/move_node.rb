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

      def self.move(verb)
        shape = MOVES.fetch(verb)
        sets :intent, :problem, :moved
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
        step(shape.fetch(:step), done: method(:tried?)) { |context| run_move(context, verb, shape) }
        gate "%{problem}", stops: :failure, pass: method(:moved?)
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
        node = context.work.public_send(verb, intent_id: context.intent_id, id: context.id, **fields(context, shape))
        context[:problem] = node ? nil : refusal(context, shape.fetch(:state))
        context[:moved] = !context.problem
      end

      def self.fields(context, shape) = shape.fetch(:fields).to_h { |name, source| [name, context.public_send(source || name)] }

      def self.refusal(context, state)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal(state) : "no node #{id} in intent #{intent_id}"
      end
    end
  end
end
