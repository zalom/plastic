# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "worktree"

module Plastic
  module Workflows
    # Prints an intent's lock row: the session, the mode, when it was taken
    # and renewed, and whether it is still live; then the code worktree when
    # the store's project names a repository. Refuses an unknown id.
    class ShowLock < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :intent, :state

      read "find the intent" do |context|
        context[:intent] = context.retrieval.intent(context.intent_id)
      end

      gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }

      read "print the lock and the worktree" do |context|
        lock = context.retrieval.lock(context.intent_id)
        context[:state] = state_of(lock)
        context.print(lock ? described(lock, context.state) : "lock: none")
        worktree = Worktree.of(context.scope, context.intent)
        context.print("worktree: #{worktree.path}") if worktree
      end

      def self.state_of(lock)
        return "none" unless lock

        lock.live? ? "live" : "expired"
      end

      def self.described(lock, state)
        "lock: session #{lock.session_id}, mode #{lock.mode}, taken #{lock.taken_at}, renewed #{lock.renewed_at}, #{state}"
      end

      outcome :none, if: ->(context) { context.state == "none" }, offers: "plastic auto %{intent_id}",
        because: "intent %{intent_id} holds no lock"
      outcome :expired, if: ->(context) { context.state == "expired" }, offers: "plastic auto %{intent_id}",
        because: "the lock of intent %{intent_id} expired, and plastic auto takes it over"
      outcome :live, offers: "plastic intent brief %{intent_id}", because: "a live session holds intent %{intent_id}"
    end
  end
end
