# frozen_string_literal: true

require_relative "../../routine"
require_relative "../../cli/sync_options"

module Plastic
  module Commands
    module Sync
      # Reads the files people changed into rows.
      # A record changed on both sides stops the call, exit 3, and every
      # conflict is listed.
      # With one home after the other and a copy of the files between, no change is lost; with a command on each home before the copy, the file that arrives takes the place of the change of the second home.
      # A file deleted on one home is printed again from rows on the other.
      class Up < Routine
        extend CLI::SyncOptions

        option :dry_run, switch: "--dry-run", default: false, text: "preview the complete sync in a disposable copy"

        workflow :code_preview_sync do
          on :done, next: :noop
          on :continue, next: :code_sync_up
        end
        workflow :code_sync_up, next: :noop
      end
    end
  end
end
