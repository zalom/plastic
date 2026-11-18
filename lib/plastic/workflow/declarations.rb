# frozen_string_literal: true

require_relative "../invalid"
require_relative "outcome"

module Plastic
  class Workflow
    # What a workflow's class body declares: the facts it sets, its summary and its outcome lines.
    module Declarations
      # The facts this workflow sets. The routine declares them on the context.
      def sets(*names) = facts.concat(names)

      def facts = (@facts ||= [])

      def summary(text = nil) = text ? (declared[:summary] = text) : declared[:summary]

      def declared = (@declared ||= {})

      # One way the workflow ends. `offers:` is the command next: prints and
      # `because:` the line that says why; both matter only when the outcome
      # ends the chain. Each lane adds its own rules.
      def outcome(outcome_name, **options)
        unknown = options.keys - %i[if offers because stops found_by unreachable words]
        raise Invalid, "#{name}: outcome #{outcome_name} does not take #{unknown.join(", ")}" if unknown.any?

        outcomes << Outcome.new(outcome_name, *options.values_at(:if, :offers, :because, :stops, :found_by, :unreachable, :words))
      end

      def outcomes = (@outcomes ||= [])

      # The outcome line that can end the chain on `outcome_name`: the one that
      # gives its because: line. Nil when no line does.
      def ending(outcome_name) = outcomes.select(&:because).find { |outcome| outcome.name == outcome_name }

      # The next: and because: lines for an outcome that ends the chain.
      def closing(outcome_name, ctx)
        found = ending(outcome_name)
        raise Invalid, "#{key} ends on #{outcome_name}, and no outcome line gives its because:" unless found

        found.closing(ctx)
      end

      # Every %{name} this workflow prints. Routine.verify checks them.
      def templates = outcomes.flat_map(&:templates)

      # Empties the lists the class body fills, so a second load of the class replaces the first.
      def clear_declarations
        facts.clear
        outcomes.clear
        declared.clear
      end
    end
  end
end
