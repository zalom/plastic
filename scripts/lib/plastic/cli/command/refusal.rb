# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # A gate stopped the call, and the owner holds the step: exit 3. The
      # error prints its own line.
      class Refusal < StandardError
        def exit_code = REFUSED

        def report(output) = output.refused(message)
      end
    end
  end
end
