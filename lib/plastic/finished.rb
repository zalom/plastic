# frozen_string_literal: true

require_relative "end_value"
require_relative "errors"

module Plastic
  # The workflows reached their end: next: names the outcome's offer, or none. Exit 0.
  #
  # A routine ends in a value, Finished or HandedOff, or in an error that
  # stops it: Failed, Refused or Usage. Each ending is named after the command
  # run status it leaves and has its own exit code; no workflow picks a
  # number, so exit 8 cannot exist.
  #
  #   Finished   exit 0  the workflows reached their end
  #   HandedOff  exit 0  the agent has steps to do; 1 with stops: :failure
  #   Failed     exit 1  a step broke, or a gate stopped the call as a failure
  #   Refused    exit 3  a gate stopped the call as a refusal: the owner's step
  #
  # The printed lines live on the Context, not on these values.
  Finished = Data.define(:next_command, :because) do
    include EndValue

    # The end of the call on `outcome` of `workflow`, with its closing
    # lines. A closing line that cannot fill fails the call.
    def self.closing(workflow, outcome, ctx)
      command, because = workflow.closing(outcome, ctx)
      new(next_command: command, because:)
    rescue Usage, Failed, Refused
      raise
    rescue => error
      raise Failed.raised(workflow.key, "closing", error)
    end

    def exit_code = 0

    def report(output)
      output.next_step(next_command, because:)
      exit_code
    end
  end
end
