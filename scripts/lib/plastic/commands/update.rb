# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Syncs a newer running package into the home, or names the installer
    # command that fetches the newest release of the channel.
    class Update < Routine
      option :dry_run, switch: "--dry-run", default: false, text: "name both versions and change nothing"

      workflow :code_preview_update do
        on :done, next: :noop
        on :continue, next: :code_update_plastic
      end
      workflow :code_update_plastic, next: :noop

      private

      def keeps_routine_run? = false
    end
  end
end
