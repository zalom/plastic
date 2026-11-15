# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Every store under the Plastic home, its intents by group, and
    # their node counts by state.
    class Status < Routine
      opens_no_store

      workflow :code_show_status, next: :noop
    end
  end
end
