# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Switches the active release back to the previous one, or to a named
    # installed release. A dry run names the switch and changes nothing.
    class Rollback < Routine
      option :target, switch: "--version VERSION", text: "an installed release to switch to"
      option :dry_run, switch: "--dry-run", default: false, text: "name the switch and change nothing"

      workflow :code_preview_rollback do
        on :done, next: :noop
        on :continue, next: :code_rollback_release
      end
      workflow :code_rollback_release, next: :noop

      private

      def keeps_routine_run? = false
    end
  end
end
