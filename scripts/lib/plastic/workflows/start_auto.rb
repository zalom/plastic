# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/spec"
require_relative "worktree"

module Plastic
  module Workflows
    # Arms delivery on an intent: refuses an open decision, no done
    # criteria, a done or abandoned intent, or another session's live lock;
    # fails with no session named; otherwise takes the lock and goes active,
    # then prints the code worktree when the store's project names a repository.
    class StartAuto < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :problem, :intent, :worktree_command

      read "read the intent and its spec" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:problem] = problem_for(context)
      end

      def self.problem_for(context)
        id = context.intent_id
        state_problem(id, context.intent) || spec_problem(id, context) || lock_problem(id, context)
      end

      def self.state_problem(id, intent)
        return nil unless intent
        return "intent #{id} is #{intent.status}" unless intent.open?

        nil
      end

      def self.spec_problem(id, context)
        spec = Graph::Knowledge::Spec.new(context.retrieval, id)
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

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
      gate "plastic auto names no session", stops: :failure, pass: ->(context) { !context.session.nil? }
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
        context.work.print_intent(context.intent_id)
      end

      read "name the code worktree" do |context|
        context[:worktree_command] = nil
        name_worktree(context, Worktree.of(context.scope, context.intent))
      end

      # Prints the worktree and its branch; while the folder does not exist,
      # the command that adds it becomes the next: line.
      def self.name_worktree(context, worktree)
        return unless worktree

        context.print("worktree: #{worktree.path}")
        context.print("branch: #{worktree.branch}")
        context[:worktree_command] = worktree.command unless worktree.present?
      end

      outcome :worktree, if: ->(context) { !context.worktree_command.nil? }, offers: "%{worktree_command}",
        because: "intent %{intent_id} is active and its code worktree does not exist yet"
      outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} is active"
    end
  end
end
