# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Prints each backup folder of the store with its start time, status and
    # goal, flagging a missing or changed file. A flag fails the call.
    class BackupList < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      FAILING = %w[changed missing].freeze

      sets :flagged

      read "print each backup" do |context|
        entries = context.work.backups.entries
        context[:flagged] = entries.any? { |entry| FAILING.include?(entry.flag) }
        entries.each { |entry| print_entry(context, entry) }
        context.print("no backups") if entries.empty?
      end

      def self.print_entry(context, entry)
        suffix = entry.flag ? " (#{entry.flag})" : ""
        context.print("#{entry.number}  #{entry.folder}  #{entry.started}  #{entry.status}  #{entry.goal}#{suffix}")
      end

      gate "a backup is missing or changed; see above", stops: :failure, pass: ->(context) { !context.flagged }

      outcome :done, offers: "plastic backup --store %{store}", because: "every backup with a row is on disk and unchanged"
    end
  end
end
