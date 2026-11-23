# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "node_output"
require_relative "../harnesses/run_record"

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
                        offers: "plastic node claim %{intent_id} %{id} --agent NAME" },
        done_node: { state: "done", step: "finish the node", say: "say what was done", fields: { findings: :text },
                     offers: "plastic graph ready %{intent_id}" },
        fail_node: { state: "failed", step: "fail the node", say: "say what failed", fields: { reason: :text },
                     offers: "plastic node release %{intent_id} %{id}" },
        ask_node: { state: "needs_info", step: "ask the owner", say: "say what was asked", fields: { question: :text },
                    offers: "plastic node resolve %{intent_id} %{id} TEXT" },
        impede_node: { state: "impeded", step: "record the impediment", say: "say what impedes the node", fields: { reason: :text },
                       offers: "plastic node resolve %{intent_id} %{id} TEXT" },
        resolve_node: { state: "open", step: "resolve the node", say: "say what was resolved", fields: { answer: :text },
                        offers: "plastic node claim %{intent_id} %{id} --agent NAME" },
        remove_node: { state: "removed", step: "remove the node", say: "say what was removed", fields: %i[reason],
                       offers: "plastic graph ready %{intent_id}" }
      }.freeze

      RESULT_VERBS = %i[done_node fail_node ask_node impede_node].freeze
      # The moves that end a run, so what the harness's record holds of it is read and kept.
      RUN_ENDS = (RESULT_VERBS + [:release_node]).freeze
      # The read of a run's usage runs this many seconds past the end the run stores, which is cut to whole seconds.
      END_SECOND = 1

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
        sets :intent, :problem, :moved, :held_elsewhere
        intent_steps
        output_steps if verb == :done_node
        move_steps(verb, shape)
        result_steps(shape)
      end

      def self.intent_steps
        read("find the intent") { |context| context[:intent] = context.retrieval.intent(context.intent_id) }
        gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { context.intent }
      end

      # The file of `--output`, read and checked before the node moves: output that is not JSON leaves the node claimed.
      def self.output_steps
        sets :output_text, :output_problem
        read("read the output file") { |context| read_output(context) }
        gate "%{output_problem}", stops: :failure, offers: "plastic node fail %{intent_id} %{id} TEXT",
          because: "output that is not JSON is not stored; node %{id} stays claimed, so finish it again or fail it",
          pass: ->(context) { context.output_problem.nil? }
      end

      def self.read_output(context)
        context[:output_text], context[:output_problem] = context.output ? NodeOutput.read(context.output) : [nil, nil]
      end

      def self.move_steps(verb, shape)
        read("forget a refusal of an earlier call") { |context| forget_refusal(context) }
        step(shape.fetch(:step), done: method(:tried?), changes: { work: CHANGES.fetch(verb) }) { |context| run_move(context, verb, shape) }
        gate "%{problem}", stops: :refusal,
          words: "another session took the claim of the node after it lapsed",
          pass: ->(context) { !context.held_elsewhere }
        move_gates
      end

      def self.move_gates
        gate "%{problem}", stops: :failure,
          words: "the node is not in the intent",
          pass: ->(context) { moved?(context) || !context.retrieval.node(context.intent_id, context.id).nil? }
        gate "%{problem}", stops: :refusal,
          words: "the state of the node does not allow this move",
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
        node = context.work.public_send(verb, intent_id: context.intent_id, id: context.id, by: context.session, **fields(context, shape), **files(context, verb), **stored_output(context, verb))
        settle(context, node || (verb == :done_node && repeated_done?(context)), shape.fetch(:state))
        record_usage(context) if node && RUN_ENDS.include?(verb)
      end

      # Keeps on the run just ended what the record of its harness holds. A record that is missing or unreadable is named in the
      # run's note, and the move stands either way.
      def self.record_usage(context)
        intent_id, id = context.intent_id, context.id
        ended = [finisher_run(context, context.retrieval.node(intent_id, id))].compact.select(&:ended_at)
        ended.each { |run| context.work.record_run(intent_id:, id:, by: context.session, usage: read_usage(context, run, "#{intent_id} #{id}")) }
      end

      # The run's end is stored in whole seconds, and the worker's turn that ran the done command is written before the command reads
      # the clock, so it can fall up to one second after the stored end. The read runs to the end of that second.
      def self.read_usage(context, run, claim)
        Harnesses::RunRecord.new(home: context.user_home.to_s).read(harness: run.harness, session: run.session_id,
          from: Time.iso8601(run.started_at), to: Time.iso8601(run.ended_at) + END_SECOND, claim:)
      end

      def self.settle(context, moved, state)
        context[:problem] = moved ? nil : refusal(context, state)
        context[:held_elsewhere] = !moved && held_elsewhere?(context)
        context[:moved] = !context.problem
      end

      def self.fields(context, shape) = shape.fetch(:fields).to_h { |name, source| [name, context.public_send(source || name)] }

      def self.stored_output(context, verb) = (verb == :done_node && context.output_text) ? { output: context.output_text } : {}

      def self.files(context, verb) = RESULT_VERBS.include?(verb) ? { files: context.files } : {}

      def self.held_elsewhere?(context)
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
      def self.finisher_of(context, node) = finisher_run(context, node)&.session_id

      def self.finisher_run(context, node)
        context.retrieval.structure.runs(node.intent_id).select { |run| run.node_id == node.id }.max_by(&:number)
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

        held_elsewhere?(context) ? "node #{id} is held by session #{node.claimed_by || finisher_of(context, node)}; its claim was taken" : node.refusal(state)
      end
    end
  end
end
