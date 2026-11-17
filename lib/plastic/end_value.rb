# frozen_string_literal: true

module Plastic
  # What every end of a call leaves on its command run: the status and the lines it keeps.
  module EndValue
    def status = Plastic.snake(self.class.name.split("::").last)

    def record = { status:, next_command:, because:, exit_code: }
  end
end
