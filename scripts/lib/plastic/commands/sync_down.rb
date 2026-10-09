# frozen_string_literal: true

require_relative "../routine"
require_relative "../cli/sync_options"

module Plastic
  module Commands
    # Prints the rows that changed into files.
    # A record changed on both sides stops the call, exit 3, and every
    # conflict is listed.
    class SyncDown < Routine
      extend CLI::SyncOptions

      option :dry_run, switch: "--dry-run", default: false, text: "preview the complete sync in a disposable copy"

      workflow :code_preview_sync_down do
        on :done, next: :noop
        on :continue, next: :code_sync_down
      end
      workflow :code_sync_down, next: :noop

      private
    end
  end
end
