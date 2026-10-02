# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # One shared shape for every workflow that moves a node through a
    # single state change: run the move, gate on its refusal, print the
    # result, and offer what comes next. A subclass calls `move` once,
    # naming only what differs between moves.
    class MoveNode < CodeWorkflow
      def self.move(verb, **shape, &fields)
        sets :problem, :moved
        define_move(verb, shape, fields)
        gate "%{problem}", stops: :refusal, pass: ->(context) { context.moved }
        read(shape.fetch(:say)) { |context| context.print("node: #{context.id} #{shape.fetch(:state)}") }
        outcome :done, **shape.fetch(:result)
      end

      def self.define_move(verb, shape, fields)
        fields ||= ->(_context) { {} }
        state = shape.fetch(:state)

        step shape.fetch(:step_name), done: ->(context) { context.facts.key?(:moved) } do |context|
          record_move(context, state, node_for(context, verb, fields))
        end
      end

      def self.node_for(context, verb, fields)
        context.work.public_send(verb, intent_id: context.intent_id, id: context.id, **fields.call(context))
      end

      def self.record_move(context, state, node)
        context[:moved] = node ? true : false
        context[:problem] = node ? nil : refusal(context, state)
      end

      def self.refusal(context, state)
        intent_id, id = context.intent_id, context.id
        node = context.retrieval.node(intent_id, id)
        node ? node.refusal(state) : "no node #{id} in intent #{intent_id}"
      end
    end
  end
end
