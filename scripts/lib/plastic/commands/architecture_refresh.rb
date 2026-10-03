# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Tells the agent to regenerate the project's architecture map with its own tool.
    class ArchitectureRefresh < Routine
      workflow :agent_refresh_architecture, next: :noop
    end
  end
end
