# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "backup_purge"

module Plastic
  module Workflows
    # Lists the backups a purge would delete, and deletes nothing.
    class PreviewBackupPurge < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      read "preview the purge" do |context|
        next unless context.dry_run

        BackupPurge.targets(context).each { |name| context.print("preview: purge #{context.store}/#{name}") }
        context.print("preview: the original store was not changed")
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
        because: "the preview deleted nothing"
      outcome :continue, offers: "plastic backup purge --store %{store}", because: "apply the requested purge"
    end
  end
end
