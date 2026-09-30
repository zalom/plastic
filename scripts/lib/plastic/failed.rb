# frozen_string_literal: true

module Plastic
  # A step raised, its done check still fails after the body ran, or a gate
  # with stops: :failure stopped the call. Exit 1; the message goes to stderr
  # through the Failure error the boundary prints.
  Failed = Data.define(:workflow, :step, :reason) do
    def exit_code = 1

    def message = "#{workflow}, #{step}: #{reason}"

    def report(_output) = raise(CLI::Command::Failure, message)
  end
end
