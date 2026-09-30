# frozen_string_literal: true

require_relative "../routine"
require_relative "sync_options"

module Plastic
  module Commands
    # Reads the files people changed into rows.
    # A record changed on both sides stops the call, exit 3, and every
    # conflict is listed.
    class SyncUp < Routine
      extend SyncOptions

      workflow :code_sync_up, next: :noop
    end
  end
end
