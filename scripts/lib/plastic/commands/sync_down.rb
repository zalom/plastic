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

      workflow :code_sync_down, next: :noop
    end
  end
end
