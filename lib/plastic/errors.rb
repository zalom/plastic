# frozen_string_literal: true

require_relative "end_value"

module Plastic
  # What stops a call: a message, the command next: offers, the line because:
  # gives, and the place that raised it. Each class has its own exit code.
  class Error < StandardError
    include EndValue

    attr_reader :next_command, :source

    def initialize(message = nil, next_command: nil, because: nil, source: nil)
      super(message)
      @next_command = next_command
      @because = because
      @source = source
    end

    def because = @because || message

    def rebuilt(message) = self.class.new(message, next_command:, because: @because, source:)
  end

  # The call was made wrong. Exit 2.
  class Usage < Error
    def exit_code = 2
  end

  # A step broke, its done check still fails, or a gate stopped the call as a failure. Exit 1.
  class Failed < Error
    def self.raised(workflow, step, error) = Crashed.new(describe(error), source: "#{workflow}, #{step}")

    def self.describe(error) = [("#{error.class}: " unless error.is_a?(Failed)), error.message].join

    def exit_code = 1

    # A stop the workflow designed says only its message; the place that raised it stays in the run log.
    def tell(output, offer) = output.failed(message, offer)
  end

  # A step raised an exception nobody planned for. Exit 1, and the answer names the place that broke.
  class Crashed < Failed
    def tell(output, offer) = output.failed(message, offer, source:)

    # The command run keeps the status of every failed call: the crash is a kind of failure, not a new status.
    def status = "failed"
  end

  # The owner holds this step: a gate stopped the call as a refusal. Exit 3.
  class Refused < Error
    def exit_code = 3

    def tell(output, offer) = output.refused(message, offer)
  end
end
