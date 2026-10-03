# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # The version of the package this command came from, its channel and the
    # file it was read from.
    class Version < Routine
      workflow :code_show_version, next: :noop

      private

      def keeps_routine_run? = false
    end
  end
end
