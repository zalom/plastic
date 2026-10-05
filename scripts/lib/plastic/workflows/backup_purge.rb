# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../graph/knowledge/backup/older_than"

module Plastic
  module Workflows
    # Deletes the backup folders of one store with their rows: all of them, or
    # those strictly before a time. A row with no folder goes with them.
    class BackupPurge < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :purged

      # The folder names and orphan row names the call would delete.
      def self.targets(context)
        text = context.older_than
        cutoff = text && Graph::Knowledge::Backup::OlderThan.parse(text)
        purger = context.work.backups.purger
        (purger.names(older_than: cutoff) | purger.orphans(older_than: cutoff)).sort
      end

      step "delete the backups", done: ->(context) { !context.purged.nil? } do |context|
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
