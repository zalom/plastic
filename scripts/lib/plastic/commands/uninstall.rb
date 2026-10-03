# frozen_string_literal: true

require_relative "../routine"
require_relative "../cli/agent_options"

module Plastic
  module Commands
    # Removes the files Plastic registered with the chosen agents. The home
    # and its stores stay.
    class Uninstall < Routine
      extend CLI::AgentOptions

      workflow :code_preview_uninstall do
        on :done, next: :noop
        on :continue, next: :code_uninstall_plastic
      end
      workflow :code_uninstall_plastic, next: :noop

      private

      def keeps_routine_run? = false
    end
  end
end
