# frozen_string_literal: true

module Plastic
  class Workflow
    # One way the workflow ends: the outcome's name, the check that picks it,
    # the command next: prints, the line because: prints, and how it stops.
    # An outcome with no check is the fallback: it always holds.
    Outcome = Data.define(:name, :check, :offers, :because, :stops) do
      def fallback? = !check

      def holds?(ctx) = fallback? || check.call(ctx)

      # The next: command, nil when the outcome offers none, and the because: line, filled from the facts.
      def closing(ctx) = [offers ? ctx.fill(offers) : nil, ctx.fill(because)]

      def templates = [offers, because].compact
    end
  end
end
