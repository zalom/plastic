# frozen_string_literal: true

require_relative "../backup"
require_relative "../../../code_workflow"
require_relative "../../../graph/backup/older_than"

module Plastic
  module Workflows
    module Code
      class Backup
        # Deletes the backup folders of one store: all of them, or
        # those strictly before a time, or those that failed.
        class Purge < CodeWorkflow
          clear_declarations
          summary "Deletes the chosen backup folders of one store."

          sets :purged

          # The folder names the call would delete.
          def self.targets(context)
            purger = context.work.backups.purger
            return purger.failed if context.failed

            text = context.older_than
            cutoff = text && Plastic::Graph::Backup::OlderThan.parse(text)
            purger.names(older_than: cutoff)
          end

          step "delete the backups", done: ->(context) { !context.purged.nil? },
            changes: { backups: "The chosen backup folders are deleted" } do |context|
            purger = context.work.backups.purger
            names = targets(context)
            names.each { |name| purger.remove(name) }
            context[:purged] = names
          end

          read "say what was deleted" do |context|
            context.purged.each { |name| context.print("purged: #{context.store}/#{name}") }
            context.print("purged: nothing") if context.purged.empty?
          end

          outcome :done, offers: "plastic backup list --store %{store}", because: "the backups named above are gone"
        end
      end
    end
  end
end
