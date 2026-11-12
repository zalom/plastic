# frozen_string_literal: true

require_relative "end_value"

module Plastic
  # A step raised, its done check still fails after the body ran, or a gate
  # with stops: :failure stopped the call. Exit 1; the reason goes to stderr
  # through the Failure error the boundary prints; the workflow key stays
  # in the JSON error.
  Failed = Data.define(:workflow, :step, :reason, :next_command, :because) do
    include EndValue

    # The failure of a step that raised: the reason names the error.
    def self.raised(workflow, step, error) = new(workflow, step, "#{error.class}: #{error.message}")

    def initialize(workflow:, step:, reason:, next_command: nil, because: nil) = super

    def exit_code = 1

    def message = "#{workflow}, #{step}: #{reason}"

    def report(_output) = raise(CLI::Command::Failure.new(reason, next_command:, because: because || reason, source: "#{workflow}, #{step}"))
  end
end
