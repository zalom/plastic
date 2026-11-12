# frozen_string_literal: true

module Plastic
  # What every end value leaves on its routine run. A value that stops the
  # call, Failed or Refused, has a message, and the message is the because:
  # line when the value carries none.
  module EndValue
    def status = Plastic.snake(self.class.name.split("::").last)

    def next_command = nil

    def message = nil

    def record = { status:, next_command:, because: because || message, exit_code: }
  end
end
