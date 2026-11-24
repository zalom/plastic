# frozen_string_literal: true

require_relative "../../../routine"
require_relative "../../../cli/sync_options"

module Plastic
  module Commands
    module Store
      module Sync
        # Reads the files people changed into rows.
        # A record changed on both sides stops the call, exit 3, and every
        # conflict is listed.
        # With one home after the other and a copy of the files between, no change is lost; with a command on each home before the copy, the file that arrives takes the place of the change of the second home.
        # An index that another home printed sets the title, the state, the disposition, the reason and the closed time of every intent it lists. So with a command on each home before the copy, it takes back a change of this home, also on an intent that the other home never changed.
        # A file deleted on one home is printed again from rows on the other.
        class Up < Routine
          changes(knowledge: "The files kept in the store folder are read into the knowledge database")
          extend CLI::SyncOptions::Up

          backs_up_first

          holds_store_lock

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
end
