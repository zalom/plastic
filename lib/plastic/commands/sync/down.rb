# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../cli/sync_options"

module Plastic
  module Commands
    module Sync
      # Writes the rows that changed into files.
      # A record changed on both sides stops the call, exit 3, and every
      # conflict is listed.
      class Down < Routine
        changes(work: "The hash of each file printed is recorded in the work database", knowledge: "The hash of each file printed is recorded in the knowledge database", references: "The hash of each file printed is recorded in the references database")
        extend CLI::SyncOptions::Down

        option :dry_run, switch: "--dry-run", default: false, text: "preview the complete sync in a disposable copy"

        workflow :code_preview_sync_down do
          on :done, next: :noop
          on :continue, next: :code_sync_down
        end
        workflow :code_sync_down, next: :noop
      end
    end
  end
end
