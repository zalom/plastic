# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/spec"

module Plastic
  module Workflows
    # Arms delivery on an intent: refuses an open decision, no done
    # criteria, a done or abandoned intent, or another session's live lock;
    # fails with no session named; otherwise takes the lock and goes active.
    class StartAuto < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :intent

      read "read the intent and its spec" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:problem] = problem_for(context)
      end

      def self.problem_for(context)
        id = context.intent_id
        intent_problem(id, context.intent) || spec_problem(id, context) || lock_problem(id, context)
      end

      def self.intent_problem(id, intent)
        return "no intent #{id} in this store" unless intent
        return "intent #{id} is #{intent.status}" unless intent.open?

        nil
      end

      def self.spec_problem(id, context)
        spec = Graph::Spec.new(context.retrieval, id)
        return "intent #{id} has an open decision; run plastic intent spec #{id}" if spec.open_decisions.any?
        return "intent #{id} names no done criterion" if spec.done_criteria.empty?

        nil
      end

      def self.lock_problem(id, context)
        lock = context.retrieval.lock(id)
        holder = lock&.session_id
        return nil unless lock && holder != context.session && lock.live?

        "intent #{id} is locked by session #{holder}"
      end

      gate "auto start names no session", stops: :failure, pass: ->(context) { !context.session.nil? }
      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      step "take the lock and go active", done: ->(context) { context.retrieval.intent(context.intent_id).status == "active" } do |context|
        context.work.take_lock(context.intent_id, session_id: context.session, mode: "auto")
        context.work.activate_intent(context.intent_id)
        context.work.print_intent(context.intent_id)
      end

      outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} is active"
    end
  end
end
