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

      def self.plan(c, direction) = c.work.sync_plan(direction, overwrite: c.overwrite, merge: c.merge)

      # What the gates read, kept as facts.
      def self.note(c, plan)
        c[:failure] = plan.failure
        c[:conflicts] = plan.conflicts.join(", ")
        c[:merging] = plan.merging?
        c[:lines] = nil
      end

      def self.apply(c, direction) = c[:lines] = c.work.sync_apply(plan(c, direction))

      def self.say(c) = Array(c.lines).each { |line| c.print(line) }

      def sync(direction)
        sets :failure, :conflicts, :merging, :lines
        plan_steps(direction)
        apply_steps(direction)
        outcome :done, offers: "plastic continue", because: NAMES.fetch(direction)
      end

      private

      def plan_steps(direction)
        read("plan the sync") { |c| SyncSteps.note(c, SyncSteps.plan(c, direction)) }
        gate "%{failure}", stops: :failure, pass: ->(c) { c.failure.nil? }
        gate REFUSED_BEFORE, stops: :refusal, pass: ->(c) { c.conflicts.empty? || c.merging }
      end

      def apply_steps(direction)
        step("apply the changes", done: ->(c) { SyncSteps.plan(c, direction).pending.zero? }) { |c| SyncSteps.apply(c, direction) }
        read("say what changed") { |c| SyncSteps.say(c) }
        gate REFUSED_AFTER, stops: :refusal, pass: ->(c) { c.conflicts.empty? }
      end
    end
  end
end
