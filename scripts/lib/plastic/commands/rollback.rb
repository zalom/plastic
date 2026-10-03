# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Lists the version history of the home, or names the installer command
    # that brings back one version from it. It changes no file itself.
    class Rollback < Routine
      option :target, switch: "--version VERSION", text: "a version from the history to go back to"

      workflow :code_show_rollback, next: :noop

      private

      def keeps_routine_run? = false
    end
  end
end
