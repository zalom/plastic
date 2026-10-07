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

      UNREADABLE = "intent folders that could not be read, the others were read:\n%{unreadable}\n" \
                   "fix or remove each folder named, then run plastic sync up again"

      def self.plan(context, direction)
        context.work.sync_plan(direction, { overwrite: context.overwrite, merge: context.merge })
      end

      # What the gates read, kept as facts.
      def self.note(context, plan)
        context[:failure] = plan.failure
        context[:conflicts] = plan.conflicts.join(", ")
        context[:merging] = plan.merging?
        context[:unreadable] = plan.unreadable.join("\n")
        context[:lines] = nil
      end

      def self.apply(context, direction) = context[:lines] = context.work.sync_apply(plan(context, direction))

      def self.applied(direction) = ->(context) { plan(context, direction).pending.zero? }

      # No intent folder is left that could not be read.
      def self.readable?(context) = context.unreadable.empty?

      def self.say(context) = Array(context.lines).each { |line| context.print(line) }

      def self.runs?(context) = !context.failure

      # A plain call writes nothing while a conflict waits.
      def self.writes?(context) = context.conflicts.empty? || context.merging

      def self.settled?(context) = context.conflicts.empty?

      # A gate's pass: check, read at each call, so it always runs the method as it stands.
      def self.check(name) = ->(context) { public_send(name, context) }

      # Declares the whole chain, so a second load of the class replaces the first.
      def sync(direction)
        [facts, steps, outcomes].each(&:clear)
        sets :failure, :conflicts, :merging, :unreadable, :lines
        plan_steps(direction)
        apply_steps(direction)
        end_steps(direction)
      end

      private

      def end_steps(direction)
        gate UNREADABLE, stops: :failure, pass: SyncSteps.check(:readable?) if direction == :up
        outcome :done, offers: "plastic next", because: NAMES.fetch(direction)
      end

      def plan_steps(direction)
        read("plan the sync") { |context| SyncSteps.note(context, SyncSteps.plan(context, direction)) }
        gate "%{failure}", stops: :failure, pass: SyncSteps.check(:runs?)
        gate REFUSED_BEFORE, stops: :refusal, pass: SyncSteps.check(:writes?)
      end

      def apply_steps(direction)
        step("apply the changes", done: SyncSteps.applied(direction)) { |context| SyncSteps.apply(context, direction) }
        read("say what changed") { |context| SyncSteps.say(context) }
        gate REFUSED_AFTER, stops: :refusal, pass: SyncSteps.check(:settled?)
      end
    end
  end
end
