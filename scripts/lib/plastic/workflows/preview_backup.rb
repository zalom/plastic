# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Describes a backup before the write workflow stages and publishes it.
    class PreviewBackup < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :name, :files

      read "preview the backup" do |context|
        next unless context.dry_run

        plan = context.work.preview_backup
        context[:name] = plan.fetch(:name)
        context[:files] = plan.fetch(:files)
        context.print("preview: backup #{context.name}, #{context.files} databases; the original store was not changed")
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic backup",
        because: "the preview wrote no archive or metadata"
      outcome :continue, offers: "plastic backup", because: "apply the requested backup"
    end
  end
end
