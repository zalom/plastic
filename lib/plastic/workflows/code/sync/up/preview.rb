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
            sets :unreadable, :unreadable_files, :unreadable_path

            # Prints the lines of the dry run, and keeps what the real run would refuse as the facts its gates read.
            def self.show(context)
              run = context.work.preview_sync({ overwrite: context.overwrite, merge: context.merge })
              [*run.lines, "preview complete; the original store was not changed"].each { |line| context.print(line) }
              note(context, run)
            end

            def self.note(context, run)
              context[:unreadable] = run.unreadable.join("\n")
              SyncSteps.note_files(context, run.unreadable_files)
            end

            # A gate that a real run passes untouched; a dry run passes it as the real run's own gate would.
            def self.as_real(name) = ->(context) { !context.dry_run || SyncSteps.public_send(name, context) }

            read("preview the sync in an isolated copy") { |context| show(context) if context.dry_run }

            gate SyncSteps::UNREADABLE, stops: :failure, pass: as_real(:readable?)
            gate SyncSteps::UNREADABLE_FILES, stops: :failure, pass: as_real(:files_read?),
              offers: "plastic sync down --overwrite %{unreadable_path}", because: "sync up cannot read %{unreadable_path}, and its rows print it again"

            outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
              because: "the preview wrote only to a disposable copy"
            outcome :continue, offers: "plastic sync up", because: "apply the requested sync"
          end
        end
      end
    end
  end
end
