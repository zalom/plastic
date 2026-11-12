# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Tells the agent to check the project's architecture map with its own tool.
    class ArchitectureStatus < Routine
      opens_no_store

      workflow :agent_check_architecture, next: :noop
    end
  end
end
