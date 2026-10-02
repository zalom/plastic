# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Prints each backup with its size and time, flagging a missing or
    # changed file. A flag fails the call.
    class BackupList < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :flagged

      read "print each backup" do |context|
        rows = context.retrieval.backups.map { |backup| [backup, context.retrieval.backup_flag(backup)] }
        context[:flagged] = rows.any? { |(_backup, flag)| flag }
        rows.each { |backup, flag| print_row(context, backup, flag) }
      end

      def self.print_row(context, backup, flag)
        suffix = flag ? " (#{flag})" : ""
        context.print("backup: #{backup.name}, #{backup.bytes} bytes, #{backup.at}#{suffix}")
      end

      gate "a backup is missing or changed; see above", stops: :failure, pass: ->(context) { !context.flagged }

      outcome :done, offers: "plastic backup", because: "every backup is on disk and unchanged"
    end
  end
end
