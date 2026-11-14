# frozen_string_literal: true

require_relative "sync_facts"

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

      UNREADABLE_FILES = "files that cannot be read into rows, the others were read:\n%{unreadable_files}\n" \
                         "each file prints again from its rows with the command below"

      # No intent folder is left that could not be read.
      def self.readable?(context) = context.unreadable.empty?

      # No changed file is left that no reader can turn into rows.
      def self.files_read?(context) = context.unreadable_files.empty?

      def self.runs?(context) = !context.failure

      # A plain call writes nothing while a conflict waits.
      def self.writes?(context) = context.conflicts.empty? || context.merging

      def self.settled?(context) = context.conflicts.empty?

      # A gate's pass: check, read at each call, so it always runs the method as it stands.
      def self.check(name) = ->(context) { public_send(name, context) }

      # Declares the whole chain, so a second load of the class replaces the first.
      def sync(direction)
        [facts, steps, outcomes].each(&:clear)
        sets :failure, :conflicts, :merging, :unreadable, :unreadable_files, :unreadable_path, :lines
        plan_steps(direction)
        apply_steps(direction)
        end_steps(direction)
      end

      private

      def end_steps(direction)
        up_gates if direction == :up
        outcome :done, offers: "plastic next", because: NAMES.fetch(direction)
      end

      def up_gates
        gate UNREADABLE, stops: :failure, pass: SyncSteps.check(:readable?)
        gate UNREADABLE_FILES, stops: :failure, pass: SyncSteps.check(:files_read?),
          offers: "plastic sync down --overwrite %{unreadable_path}", because: "sync up cannot read %{unreadable_path}, and its rows print it again"
      end

      def plan_steps(direction)
        read("plan the sync") { |context| SyncFacts.note(context, SyncFacts.plan(context, direction)) }
        gate "%{failure}", stops: :failure, pass: SyncSteps.check(:runs?)
        gate REFUSED_BEFORE, stops: :refusal, pass: SyncSteps.check(:writes?)
      end

      def apply_steps(direction)
        step("apply the changes", done: SyncFacts.applied(direction)) { |context| SyncFacts.apply(context, direction) }
        read("say what changed") { |context| SyncFacts.say(context) }
        gate REFUSED_AFTER, stops: :refusal, pass: SyncSteps.check(:settled?)
      end
    end
  end
end
