# frozen_string_literal: true

module Plastic
  class Workflow
    # One way the workflow ends: the outcome's name, the check that picks it,
    # the command next: prints, the line because: prints, and how it stops.
    # An outcome with no check is the fallback: it always holds. found_by: names the step of the workflow that finds the outcome, unreachable: true marks an ending that no way into the workflow can reach; both are for the page that draws it.
    Outcome = Data.define(:name, :check, :offers, :because, :stops, :found_by, :unreachable) do
      def initialize(found_by: nil, unreachable: nil, **rest) = super

      def fallback? = !check

      def holds?(ctx) = fallback? || check.call(ctx)

      # The next: command, nil when the outcome offers none, and the because: line, filled from the facts.
      def closing(ctx) = [offers ? ctx.fill(offers) : nil, ctx.fill(because)]

      def templates = [offers, because].compact
    end
  end
end
