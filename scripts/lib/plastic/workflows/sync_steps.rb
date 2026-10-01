# frozen_string_literal: true

module Plastic
  module Workflows
    # The steps of a sync, in either direction: plan, stop on what cannot
    # run, refuse a plain call with conflicts before it writes, apply the
    # rest, then refuse on the conflicts left.
    module SyncSteps
      NAMES = { up: "the rows hold every file changed by hand", down: "the files hold every row that changed" }.freeze
      REFUSED_BEFORE = "changed on both sides since the last print, nothing written: %{conflicts}; " \
                       "pass --overwrite PATH, --overwrite or --merge"
      REFUSED_AFTER = "changed on both sides since the last print, left as they are: %{conflicts}; " \
                      "pass --overwrite PATH or --overwrite"

      def self.plan(context, direction)
        context.work.sync_plan(direction, { overwrite: context.overwrite, merge: context.merge })
      end

      # What the gates read, kept as facts.
      def self.note(context, plan)
        context[:failure] = plan.failure
        context[:conflicts] = plan.conflicts.join(", ")
        context[:merging] = plan.merging?
        context[:lines] = nil
      end

      def self.apply(context, direction) = context[:lines] = context.work.sync_apply(plan(context, direction))

      def self.applied(direction) = ->(context) { plan(context, direction).pending.zero? }

      def self.say(context) = Array(context.lines).each { |line| context.print(line) }

      def self.runs?(context) = !context.failure

      # A plain call writes nothing while a conflict waits.
      def self.writes?(context) = context.conflicts.empty? || context.merging

      def self.settled?(context) = context.conflicts.empty?

      def sync(direction)
        sets :failure, :conflicts, :merging, :lines
        plan_steps(direction)
        apply_steps(direction)
        outcome :done, offers: "plastic continue", because: NAMES.fetch(direction)
      end

      private

      def plan_steps(direction)
        read("plan the sync") { |context| SyncSteps.note(context, SyncSteps.plan(context, direction)) }
        gate "%{failure}", stops: :failure, pass: SyncSteps.method(:runs?)
        gate REFUSED_BEFORE, stops: :refusal, pass: SyncSteps.method(:writes?)
      end

      def apply_steps(direction)
        step("apply the changes", done: SyncSteps.applied(direction)) { |context| SyncSteps.apply(context, direction) }
        read("say what changed") { |context| SyncSteps.say(context) }
        gate REFUSED_AFTER, stops: :refusal, pass: SyncSteps.method(:settled?)
      end
    end
  end
end
