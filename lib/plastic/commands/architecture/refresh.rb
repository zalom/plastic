# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Architecture
      # Tells the agent to regenerate the project's architecture map with its own tool.
      class Refresh < Routine
        opens_no_store

        workflow :agent_refresh_architecture, next: :noop
      end
    end
  end
end
