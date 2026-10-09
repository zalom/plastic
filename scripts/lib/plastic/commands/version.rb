# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # The version of the package this command came from, its channel and the
    # file it was read from.
    class Version < Routine
      graphless

      workflow :code_show_version, next: :noop
    end
  end
end
