# frozen_string_literal: true

require_relative "end_value"
require_relative "failed"

module Plastic
  # The chain reached its end: next: names the outcome's offer, or none. Exit 0.
  #
  # A routine ends in one of four values, each named after the routine run status it
  # leaves and each with its own exit code. Each value prints its own last
  # lines through `report` and returns the exit code; no workflow picks a
  # number, so exit 8 cannot exist.
  #
  #   Finished   exit 0  the chain reached its end
  #   HandedOff  exit 0  the agent has steps to do; 1 with stops: :failure
  #   Failed     exit 1  a step broke, or a gate stopped the call as a failure
  #   Refused    exit 3  a gate stopped the call as a refusal: the owner's step
  #
  # The printed lines live on the Context, not on these values.
  Finished = Data.define(:next_command, :because) do
    include EndValue

    # The end of the chain on `outcome` of `workflow`, with its closing
    # lines. A closing line that cannot fill fails the call.
    def self.closing(workflow, outcome, ctx)
      command, because = workflow.closing(outcome, ctx)
      new(next_command: command, because:)
    rescue => error
      Failed.raised(workflow.key, "closing", error)
    end

    def exit_code = 0

    def report(output)
      output.next_step(next_command, because:)
      exit_code
    end
  end
end
