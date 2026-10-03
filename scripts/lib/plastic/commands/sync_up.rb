# frozen_string_literal: true

require_relative "../routine"
require_relative "../cli/sync_options"

module Plastic
  module Commands
    # Reads the files people changed into rows.
    # A record changed on both sides stops the call, exit 3, and every
    # conflict is listed.
    class SyncUp < Routine
      extend CLI::SyncOptions

      option :dry_run, switch: "--dry-run", default: false, text: "preview the complete sync in a disposable copy"

      workflow :code_preview_sync do
        on :done, next: :noop
        on :continue, next: :code_sync_up
      end
      workflow :code_sync_up, next: :noop

      private

      def keeps_routine_run? = !parsed[:dry_run]
    end
  end
end
