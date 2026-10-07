# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "backup_restore"

module Plastic
  module Workflows
    # Lists the databases a restore would replace, and changes nothing.
    class PreviewBackupRestore < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      read "preview the restore" do |context|
        next unless context.dry_run

        folder = BackupRestore.choose(context)
        BackupRestore.held(context, folder).each { |name| context.print("preview: restore #{name} from #{context.store}/#{folder}") }
        context.print("preview: the current databases would be backed up first; the original store was not changed")
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic backup restore --store %{store}",
        because: "the preview replaced nothing"
      outcome :continue, offers: "plastic backup restore --store %{store}", because: "apply the requested restore"
    end
  end
end
