# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"
require_relative "worktree"

module Plastic
  module Workflows
    # Arms delivery on an intent: refuses an open decision, no done
    # criteria, no go-ahead row, a done or abandoned intent, or another session's live lock;
    # fails with no session named; otherwise takes the lock and goes active,
    # then prints the code worktree when the store's project names a repository.
    class StartAuto < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :closed_problem, :spec_problem, :intent

      read "read the intent and its spec" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        id = context.intent_id
        context[:closed_problem] = state_problem(id, context.intent)
        context[:spec_problem] = criterion_problem(id, context)
        context[:problem] = decision_problem(id, context) || lock_problem(id, context) || approval_problem(id, context)
      end

      def self.state_problem(id, intent)
        return nil unless intent
        return "intent #{id} is #{intent.status}" unless intent.open?

        nil
      end

def self.criterion_problem(id, context)
  return nil unless Graph::Knowledge::Spec.new(context.retrieval, id).done_criteria.empty?

  "intent #{id} names no done criterion"
end

def self.decision_problem(id, context)
  return nil unless Graph::Knowledge::Spec.new(context.retrieval, id).open_decisions.any?

  "intent #{id} has an open decision; run plastic intent spec #{id}"
end

      def self.lock_problem(id, context)
        lock = context.retrieval.lock(id)
        holder = lock&.session_id
        return nil unless lock && holder != context.session && lock.live?

        "intent #{id} is locked by session #{holder}"
      end

      def self.approval_problem(id, context)
        return nil if context.retrieval.approval(id)

        "intent #{id} has no go-ahead; the owner approves it with plastic intent approve #{id}"
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
      gate "plastic auto names no session", stops: :failure, pass: ->(context) { !context.session.nil? }
      gate "%{closed_problem}", stops: :failure, offers: "plastic next", because: "a closed intent cannot be armed; pick other work",
        pass: ->(context) { context.closed_problem.nil? }
      gate "%{spec_problem}", stops: :failure, offers: "plastic intent spec %{intent_id}",
        because: "the spec needs a done criterion", pass: ->(context) { context.spec_problem.nil? }
      gate "%{problem}", stops: :refusal, pass: ->(context) { context.problem.nil? }

      def self.delivery_started?(context)
        retrieval = context.retrieval
        intent_id = context.intent_id
        lock = retrieval.lock(intent_id)
        retrieval.intent(intent_id).status == "active" &&
          lock&.session_id == context.session && lock.mode == "auto" && lock.live?
      end

      step "take the lock and go active", done: method(:delivery_started?) do |context|
        context.work.take_lock(context.intent_id, session_id: context.session, mode: "auto")
        context.work.activate_intent(context.intent_id)
      end

      read "name the code worktree" do |context|
        name_worktree(context, Worktree.of(context.scope, context.intent))
      end

      def self.name_worktree(context, worktree)
        return unless worktree

        context.print("worktree: #{worktree.path}")
        context.print("branch: #{worktree.branch}")
      end

      outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} is active"
    end
  end
end
