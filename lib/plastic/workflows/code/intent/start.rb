# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/spec"
require_relative "../../worktree"

module Plastic
  module Workflows
    module Code
      module Intent
        # Starts an intent for `intent start` and `intent auto`, which differ only in
        # their words: fails a done or abandoned intent, no session named or a session
        # that ended; otherwise sets a future, open or parked intent in progress, prints
        # the code worktree when the store's project names a repository, and names the
        # worktree to create when its folder is missing. An unsettled spec or a missing
        # go-ahead ends on `intent spec`.
        class Start < CodeWorkflow
          clear_declarations
          summary "Starts the intent: it goes in progress and names its worktree."

          sets :closed_problem, :spec_problem, :intent, :session_problem, :worktree_missing

          read "read the intent and its spec" do |context|
            context[:intent] = context.retrieval.intent(context.intent_id)
            context[:session_problem] = session_problem(context)
            context[:closed_problem] = closed_problem(context.intent_id, context.intent)
            context[:spec_problem] = spec_problem(context.intent_id, context)
          end

          def self.session_problem(context)
            id = context.session
            session = id && context.retrieval.session(id)
            "session #{id} ended; start a new session or resume it" if session&.ended?
          end

          def self.closed_problem(id, intent) = ("intent #{id} is #{intent.status}" if intent&.closed?)

          def self.spec_problem(id, context)
            return nil unless context.intent

            spec = Plastic::Graph::Knowledge::Spec.new(context.retrieval, id)
            return "intent #{id} names no done criterion" if spec.done_criteria.empty?
            return "intent #{id} has an open decision" if spec.open_decisions.any?

            "intent #{id} has no go-ahead" unless context.retrieval.structure.approval(id)
          end

          # The refusal a node claim gives before the owner's go-ahead.
          def self.approval_problem(id, context)
            return nil if context.retrieval.structure.approval(id)

            "intent #{id} has no go-ahead; the owner approves it with plastic intent approve #{id}"
          end

          gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { !context.intent.nil? }
          gate "%{start_words} names no session; set PLASTIC_SESSION", stops: :failure, pass: ->(context) { !context.session.nil? }
          gate "%{session_problem}", stops: :failure,
            words: "the session of the call has ended",
            pass: ->(context) { context.session_problem.nil? }
          gate "%{closed_problem}", stops: :failure, offers: "plastic next", because: "a closed intent cannot start; pick other work",
            pass: ->(context) { context.closed_problem.nil? }

          def self.delivery_started?(context) = context.retrieval.intent(context.intent_id).status == "in_progress"

          step "go in progress", done: method(:delivery_started?), changes: { work: "The intent goes in progress" } do |context|
            context.work.activate_intent(context.intent_id)
          end

          read "name the code worktree" do |context|
            name_worktree(context, Worktree.of(context.scope, context.intent))
          end

          def self.name_worktree(context, worktree)
            context[:worktree_missing] = worktree ? !File.directory?(worktree.path) : false
            announce(context, worktree) if worktree
          end

          def self.announce(context, worktree)
            context.print("worktree: #{worktree.path}")
            context.print("branch: #{worktree.branch}")
            context.print(instruction(context, worktree)) if context.worktree_missing
          end

          def self.instruction(context, worktree)
            "Create the worktree at #{worktree.path} on branch #{worktree.branch}, then run plastic #{context.start_words} #{context.intent_id} again. " \
              "Use version control as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does."
          end

          outcome :worktree_missing, if: ->(context) { context.worktree_missing }, offers: "plastic %{start_words} %{intent_id}",
            because: "the worktree of intent %{intent_id} is not made yet"
          outcome :unsettled, if: ->(context) { !context.spec_problem.nil? }, offers: "plastic intent spec %{intent_id}",
            because: "%{spec_problem}"
          outcome :done, offers: "plastic intent brief %{intent_id}", because: "intent %{intent_id} is in progress"
        end
      end
    end
  end
end
