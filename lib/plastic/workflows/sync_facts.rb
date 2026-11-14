# frozen_string_literal: true

module Plastic
  module Workflows
    # The facts a sync keeps from its plan for the gates to read, and the plan and apply calls behind them.
    module SyncFacts
      def self.plan(context, direction)
        context.work.sync_plan(direction, { overwrite: context.overwrite, merge: context.merge })
      end

      # What the gates read, kept as facts.
      def self.note(context, plan)
        context[:failure] = plan.failure
        context[:conflicts] = plan.conflicts.join(", ")
        context[:merging] = plan.merging?
        note_unreadable(context, plan)
        context[:lines] = nil
      end

      def self.note_unreadable(context, plan)
        files = plan.left_unreadable
        context[:unreadable] = plan.unreadable.join("\n")
        context[:unreadable_files] = files.map { |path, reason| "#{path}: #{reason}" }.join("\n")
        context[:unreadable_path] = files.keys.first
      end

      def self.apply(context, direction) = context[:lines] = context.work.sync_apply(plan(context, direction))

      def self.applied(direction) = ->(context) { plan(context, direction).pending.zero? }

      def self.say(context) = Array(context.lines).each { |line| context.print(line) }
    end
  end
end
