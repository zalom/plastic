# frozen_string_literal: true

module Plastic
  module Workflows
    # The steps of a sync, in either direction: plan, stop on what cannot
    # run, refuse a plain call with conflicts before it writes, apply the
    # rest, then refuse on the conflicts left.
    module SyncSteps
      NAMES = { up: "the rows hold every file changed by hand", down: "the files hold every row that changed" }.freeze

      def sync(direction)
        sets :failure, :conflicts, :merging, :lines
        plan_steps(direction)
        apply_steps(direction)
        outcome :done, offers: "plastic continue", because: NAMES.fetch(direction)
      end

      private

      def plan_steps(direction)
        read "plan the sync" do |c|
          plan = c.work.sync_plan(direction, overwrite: c.overwrite, merge: c.merge)
          c[:failure] = plan.failure
          c[:conflicts] = plan.conflicts.join(", ")
          c[:merging] = plan.merging?
          c[:lines] = nil
        end
        gate "%{failure}", stops: :failure, pass: ->(c) { c.failure.nil? }
        gate "changed on both sides since the last print, nothing written: %{conflicts}; " \
             "pass --overwrite PATH, --overwrite or --merge", stops: :refusal, pass: ->(c) { c.conflicts.empty? || c.merging }
      end

      def apply_steps(direction)
        step "apply the changes", done: ->(c) { c.work.sync_plan(direction, overwrite: c.overwrite, merge: c.merge).pending.zero? } do |c|
          c[:lines] = c.work.sync_apply(c.work.sync_plan(direction, overwrite: c.overwrite, merge: c.merge))
        end
        read "say what changed" do |c|
          Array(c.lines).each { |line| c.print(line) }
        end
        gate "changed on both sides since the last print, left as they are: %{conflicts}; " \
             "pass --overwrite PATH or --overwrite", stops: :refusal, pass: ->(c) { c.conflicts.empty? }
      end
    end
  end
end
