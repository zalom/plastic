# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Syncs a newer running package into the home, or activates the newest
    # release of the chosen channel, by default the active release's own.
    class Update < Routine
      graphless

      option :stable, switch: "--stable", default: false, text: "update from the stable channel"
      option :beta, switch: "--beta", default: false, text: "update from the beta channel"
      option :alpha, switch: "--alpha", default: false, text: "update from the alpha channel"
      option :dry_run, switch: "--dry-run", default: false, text: "name both versions and change nothing"

      workflow :code_preview_update do
        on :done, next: :noop
        on :continue, next: :code_update_plastic
      end
      workflow :code_update_plastic, next: :noop
    end
  end
end
