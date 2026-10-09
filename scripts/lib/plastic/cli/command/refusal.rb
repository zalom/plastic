# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # A gate stopped the call, and the owner holds the step: exit 3. The
      # error prints its own line, and then the next: command it carries, if any.
      class Refusal < StandardError
        attr_reader :next_command, :because

        def initialize(message = nil, next_command: nil, because: message)
          super(message)
          @next_command = next_command
          @because = because
        end

        def exit_code = REFUSED

        def report(output) = output.refused(message, next_command:, because:)

        def rebuilt(message) = self.class.new(message, next_command:, because:)
      end
    end
  end
end
