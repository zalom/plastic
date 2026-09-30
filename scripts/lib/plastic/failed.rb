# frozen_string_literal: true

require_relative "end_value"

module Plastic
  # A step raised, its done check still fails after the body ran, or a gate
  # with stops: :failure stopped the call. Exit 1; the message goes to stderr
  # through the Failure error the boundary prints.
  Failed = Data.define(:workflow, :step, :reason) do
    include EndValue

    # The failure of a step that raised: the reason names the error.
    def self.raised(workflow, step, error) = new(workflow, step, "#{error.class}: #{error.message}")

    def exit_code = 1

    def message = "#{workflow}, #{step}: #{reason}"

    def report(_output) = raise(CLI::Command::Failure, message)
  end
end
