# frozen_string_literal: true

require_relative "end_value"

module Plastic
  # The owner holds this step: a gate with stops: :refusal stopped the call.
  # Exit 3; the message goes to stderr through the Refusal error the
  # boundary prints.
  Refused = Data.define(:workflow, :reason, :next_command, :because) do
    include EndValue

    def initialize(workflow:, reason:, next_command: nil, because: nil) = super

    def exit_code = 3

    def message = reason

    def report(_output) = raise(CLI::Command::Refusal.new(message, next_command:, because: because || reason))
  end
end
