# frozen_string_literal: true

module Plastic
  # The owner holds this step: a gate with stops: :refusal stopped the call.
  # Exit 3; the message goes to stderr through the Refusal error the
  # boundary prints.
  Refused = Data.define(:workflow, :reason) do
    def exit_code = 3

    def message = reason

    def report(_output) = raise(CLI::Command::Refusal, message)
  end
end
