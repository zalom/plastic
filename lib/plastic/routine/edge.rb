# frozen_string_literal: true

module Plastic
  class Routine < CLI::Command
    # One edge of a chain: from a workflow key, on an outcome, to the next
    # key. An edge with no outcome is its workflow's plain next:, and it
    # carries every outcome.
    Edge = Data.define(:from, :on, :to) do
      def plain? = !on

      def carries?(outcome) = plain? || on == outcome

      # An on line for an outcome the workflow never returns.
      def stray?(outcomes) = !(plain? || outcomes.include?(on))

      # The wiring fault of this edge alone, or nil. Every edge points to a
      # later key, so a chain can only move forward and never loops.
      def problem(keys)
        return if to == :noop

        target = keys.index(to)
        return "#{to} is a target but not in the chain" unless target

        "#{from} -> #{to} points backward; a chain only moves forward" if target <= keys.index(from)
      end
    end
  end
end
