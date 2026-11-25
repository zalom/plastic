# frozen_string_literal: true

require_relative "../backup"
require_relative "../../../code_workflow"
require_relative "../../../graph/backup/older_than"

module Plastic
  module Workflows
    module Code
      class Backup
        # Deletes the backup folders of one store: all of them, or
        # those strictly before a time, those that failed, or those a stopped run left in progress.
        class Purge < CodeWorkflow
          clear_declarations
          summary "Deletes the chosen backup folders of one store."

          sets :purged

          # The folder names the call would delete.
          def self.targets(context)
            backups = context.work.backups
            purger = backups.purger
            return purger.failed if context.failed
            return purger.interrupted(now: backups.now) if context.interrupted

            purger.names(older_than: cutoff(context.older_than))
          end

          # The time a date text names, or nil when none was given.
          def self.cutoff(text) = text && Plastic::Graph::Backup::OlderThan.parse(text)

          step "delete the backups", done: ->(context) { !context.purged.nil? },
            changes: { backups: "The chosen backup folders are deleted" } do |context|
            purger = context.work.backups.purger
            names = targets(context)
            names.each { |name| purger.remove(name) }
            context[:purged] = names
          end

          read "say what was deleted" do |context|
            context.purged.each { |name| context.print("purged: #{context.project}/#{name}") }
            context.print("purged: nothing") if context.purged.empty?
          end

          outcome :done, offers: "plastic store backup list --project %{project}", because: "the backups named above are gone"
        end
      end
    end
  end
end
