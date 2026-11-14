# frozen_string_literal: true

require_relative "../up"
require_relative "../../../../code_workflow"
require_relative "../../../sync_steps"

module Plastic
  module Workflows
    module Code
      module Sync
        class Up
          # Previews the same sync in a copy before the normal write workflow, and refuses what the real run refuses.
          class Preview < CodeWorkflow
            [facts, steps, outcomes].each(&:clear)

            # Prints the lines of the dry run, and keeps what the real run would refuse as the facts its gates read.
            def self.show(context, direction)
              note(context, printed(context, context.work.preview_sync({ overwrite: context.overwrite, merge: context.merge }, direction:)))
            rescue Invalid => error
              context[:failure] = error.message
            end

            def self.printed(context, run)
              [*run.lines, "preview complete; the original store was not changed"].each { |line| context.print(line) }
              run
            end

            def self.note(context, run)
              context[:conflicts] = run.conflicts.join(", ")
              context[:merging] = run.merging
              context[:unreadable] = run.unreadable.join("\n")
              SyncSteps.note_files(context, run.unreadable_files)
            end

            # A gate that a real run passes untouched; a dry run passes it as the real run's own gate would.
            def self.as_real(name) = ->(context) { !DRY_RUN.call(context) || SyncSteps.public_send(name, context) }

            DRY_RUN = ->(context) { context.dry_run }

            # The steps of a preview in `direction`: the dry run, then the gates of the real run in its order.
            def self.preview(direction)
              sets :failure, :conflicts, :merging, :unreadable, :unreadable_files, :unreadable_path
              read("preview the sync in an isolated copy") { |context| show(context, direction) if DRY_RUN.call(context) }
              real_gates
              outcomes_of(direction)
            end

            def self.outcomes_of(direction)
              outcome :done, if: DRY_RUN, offers: "%{original_command}", because: "the preview wrote only to a disposable copy"
              outcome :continue, offers: "plastic sync #{direction}", because: "apply the requested sync"
            end

            def self.real_gates
              gate "%{failure}", stops: :failure, pass: as_real(:runs?)
              gate SyncSteps::REFUSED_BEFORE, stops: :refusal, pass: as_real(:writes?)
              gate SyncSteps::REFUSED_AFTER, stops: :refusal, pass: as_real(:settled?)
              readable_gates
            end

            # The gates of the files that sync up reads.
            def self.readable_gates
              gate SyncSteps::UNREADABLE, stops: :failure, pass: as_real(:readable?)
              gate SyncSteps::UNREADABLE_FILES, stops: :failure, pass: as_real(:files_read?),
                offers: "plastic sync down --overwrite %{unreadable_path}", because: "sync up cannot read %{unreadable_path}, and its rows print it again"
            end

            preview :up
          end
        end
      end
    end
  end
end
