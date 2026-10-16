# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # The call failed on something the agent can fix: exit 1. The error
      # prints its own line, and then the next: command it carries, if any.
      class Failure < StandardError
        attr_reader :next_command, :because, :source

        def initialize(message = nil, next_command: nil, because: message, source: nil)
          super(message)
          @source = source
          @next_command = next_command
          @because = because
        end

        def exit_code = FAILED

        def report(output) = output.failed(message, Offer.new(next_command, because), source:)

        def rebuilt(message) = self.class.new(message, next_command:, because:, source:)
      end
    end
  end
end
