# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # The call failed on something the agent can fix: exit 1. The error
      # prints its own line.
      class Failure < StandardError
        def exit_code = FAILED

        def report(output) = output.failed(message)
      end
    end
  end
end
