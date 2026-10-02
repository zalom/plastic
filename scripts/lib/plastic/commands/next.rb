# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Picks the intent this session is working on and offers its next command.
    class Next < Routine
      reads :work, :knowledge
      workflow :code_pick_next, next: :noop
    end
  end
end
