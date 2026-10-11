# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "worktree"
require_relative "go_ahead"

module Plastic
  module Workflows
    # Prints an intent's lock row: the session, the mode, when it was taken
    # and renewed, whether it is still live and why; then the code worktree when
    # the store's project names a repository. Refuses an unknown id.
    class ShowLock < CodeWorkflow
      extend GoAhead

      [facts, steps, outcomes].each(&:clear)

      sets :intent, :state, :status, :why, :handoff_text

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
        context[:status] = context.intent&.status
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "print the lock and the worktree" do |context|
        lock = context.retrieval.lock(context.intent_id)
        liveness = lock && context.retrieval.liveness(lock)
        context[:state] = state_of(liveness)
        context.print(liveness ? described(liveness, context.state) : "lock: none")
        worktree = Worktree.of(context.scope, context.intent)
        context.print("worktree: #{worktree.path}") if worktree
      end

      reads_go_ahead

      def self.state_of(liveness)
        return "none" unless liveness

        liveness.live? ? "live" : "expired"
      end

      def self.described(liveness, state)
        lock = liveness.lock
        "lock: session #{lock.session_id}, mode #{lock.mode}, taken #{lock.taken_at}, renewed #{lock.renewed_at}, #{state}: #{liveness.why}"
      end

      outcome :closed, if: ->(context) { %w[done abandoned].include?(context.intent.status) }, offers: nil,
        because: "intent %{intent_id} is %{status}"
      outcome :agent_needed, if: ->(context) { context.state != "live" && !context.handoff_text.nil? }
      outcome :none, if: ->(context) { context.state == "none" }, offers: "plastic auto %{intent_id}",
        because: "intent %{intent_id} holds no lock"
      outcome :expired, if: ->(context) { context.state == "expired" }, offers: "plastic auto %{intent_id}",
        because: "the lock of intent %{intent_id} expired, and plastic auto takes it over"
      outcome :live, offers: "plastic intent brief %{intent_id}", because: "a live session holds intent %{intent_id}"
    end
  end
end
