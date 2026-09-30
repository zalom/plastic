# frozen_string_literal: true

module Plastic
  # What every end value leaves on its routine run. A value that stops the
  # call, Failed or Refused, has no next command, and its message is the
  # because: line.
  module EndValue
    def status = Plastic.snake(self.class.name.split("::").last)

    def next_command = nil

    def because = message

    def record = {status:, next_command:, because:, exit_code:}
  end
end
