# frozen_string_literal: true

require_relative "../backup"
require_relative "../../../code_workflow"
require_relative "../../../graph/knowledge/backup/databases"

module Plastic
  module Workflows
    module Code
      class Backup
        # Says which folder and databases a backup would write, and writes nothing.
        class Preview < CodeWorkflow
          [facts, steps, outcomes].each(&:clear)

          read "preview the backup" do |context|
            next unless context.dry_run

            plan = context.work.backups.plan(databases: Plastic::Graph::Knowledge::Backup::Databases.parse(context.databases))
            context.print("preview: backup #{context.store}/#{plan.fetch(:folder)}, #{plan.fetch(:databases).join(", ")}; the original store was not changed")
          end

          outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
            because: "the preview wrote no folder or row"
          outcome :continue, offers: "plastic backup --store %{store}", because: "apply the requested backup"
        end
      end
    end
  end
end
