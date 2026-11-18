# frozen_string_literal: true

require_relative "sync_words"
require_relative "sync_refusals"
require_relative "type_notice"

module Plastic
  module Workflows
    # The steps of a sync, in either direction: plan, stop on what cannot
    # run, refuse a plain call with conflicts before it writes, apply the
    # rest, then refuse on the conflicts left.
    module SyncSteps
      CHANGES = {
        up: {
          home: "The file types a sync skipped are recorded in the setting sync.asked, once each",
          work: "The records of the intents whose files changed by hand are rewritten from the files",
          knowledge: "The documents of those intents are rewritten from the files",
          store: "The files of the intents and the index of the store are printed again from the rows"
        },
        down: { store: "The files of the intents whose records changed are rewritten in the store folder, and a savepoint.md that matches its print is removed for work.log" }
      }.freeze

      def self.plan(context, direction)
        context.work.sync_plan(direction, { overwrite: context.overwrite, merge: context.merge })
      end

      # What the gates read, kept as facts.
      def self.note(context, plan)
        note_refusals(context, plan)
        note_files(context, plan.unreadable_files, plan.rowless_files)
        context[:lines] = plan.old_savepoints.kept_lines.then { |kept| kept unless kept.empty? }
      end

      def self.note_refusals(context, plan)
        context[:failure] = plan.failure
        context[:conflicts] = plan.conflicts.join(" ")
        context[:merging] = plan.merging?
        context[:unreadable] = plan.unreadable.join("\n")
      end

      # `rowless` names the files this home holds no rows for: a print from rows cannot work here, so no command is offered for them.
      def self.note_files(context, files, rowless = [])
        context[:unreadable_files] = files.map { |path, reason| "#{path}: #{reason}; #{fix_of(path, rowless)}" }.join("\n")
        keys = files.keys
        context[:unreadable_path] = (keys - rowless).first
        context[:unreadable_rowless] = (keys & rowless).first
      end

      def self.fix_of(path, rowless) = rowless.include?(path) ? SyncWords::REPRINTED_ELSEWHERE : "run plastic sync down --overwrite #{path}"

      # The lines of the apply, and the files it found no row would take: a new plan names them.
      def self.apply(context, direction)
        planned = plan(context, direction)
        context[:lines] = [*context.work.sync_apply(planned), *new_type_lines(context, planned)]
        note_remaining(context, direction)
      end

      def self.new_type_lines(context, planned)
        (planned.direction == :up) ? TypeNotice.new(context.settings.config).lines(planned.new_types) : []
      end

      def self.note_remaining(context, direction)
        after = plan(context, direction)
        note_files(context, after.unreadable_files, after.rowless_files)
      end

      def self.applied(direction) = ->(context) { plan(context, direction).pending.zero? }

      # No intent folder is left that could not be read.
      def self.readable?(context) = context.unreadable.empty?

      # No changed file is left that no reader can turn into rows.
      def self.files_read?(context) = context.unreadable_path.nil?

      # No changed file is left that this home holds no rows for.
      def self.rowless_read?(context) = context.unreadable_rowless.nil?

      def self.say(context) = Array(context.lines).each { |line| context.print(line) }

      def self.runs?(context) = !context.failure

      # A plain call writes nothing while a conflict waits.
      def self.writes?(context) = context.conflicts.empty? || context.merging

      def self.settled?(context) = context.conflicts.empty?

      # A gate's pass: check, read at each call, so it always runs the method as it stands.
      def self.check(name) = ->(context) { public_send(name, context) }

      # Declares the whole chain, so a second load of the class replaces the first.
      def sync(direction)
        clear_declarations
        sets :failure, :conflicts, :merging, :unreadable, :unreadable_files, :unreadable_path, :unreadable_rowless, :lines
        plan_steps(direction)
        apply_steps(direction)
        end_steps(direction)
      end

      private

      def end_steps(direction)
        up_gates if direction == :up
        outcome :done, offers: "plastic next", because: SyncWords::NAMES.fetch(direction)
      end

      def up_gates
        gate SyncWords::UNREADABLE, stops: :failure, pass: SyncSteps.check(:readable?)
        gate SyncWords::UNREADABLE_FILES, stops: :failure, pass: SyncSteps.check(:files_read?),
          offers: "plastic sync down --overwrite %{unreadable_path}", because: "sync up cannot read %{unreadable_path}, and its rows print it again"
        gate SyncWords::UNREADABLE_FILES, stops: :failure, pass: SyncSteps.check(:rowless_read?),
          because: "sync up cannot read %{unreadable_rowless}, and this home holds no rows to print it again"
      end

      def plan_steps(direction)
        read("plan the sync") { |context| SyncSteps.note(context, SyncSteps.plan(context, direction)) }
        gate "%{failure}", stops: :failure,
          words: SyncWords::PLAN_FAILURES.fetch(direction),
          pass: SyncSteps.check(:runs?)
        gate SyncRefusals::REFUSED_BEFORE.fetch(direction), stops: :refusal, pass: SyncSteps.check(:writes?)
      end

      def apply_steps(direction)
        step("apply the changes", done: SyncSteps.applied(direction), changes: CHANGES.fetch(direction)) { |context| SyncSteps.apply(context, direction) }
        read("say what changed") { |context| SyncSteps.say(context) }
        gate SyncRefusals::REFUSED_AFTER.fetch(direction), stops: :refusal, pass: SyncSteps.check(:settled?)
      end
    end
  end
end
