# frozen_string_literal: true

require_relative "end_value"

module Plastic
  # The agent has steps to do, and the next call checks them. Exit 0, or 1
  # when the workflow's handoff outcome says stops: :failure.
  HandedOff = Data.define(:steps, :next_command, :because, :exit_code) do
    include EndValue

    def report(output)
      steps.each.with_index(1) { |step, number| output.raw("#{number}. #{step}") }
      output.next_step(next_command, because:)
      exit_code
    end
  end
end
