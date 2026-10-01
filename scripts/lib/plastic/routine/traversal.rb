# frozen_string_literal: true

require_relative "../finished"

module Plastic
  class Routine < CLI::Command
    # One pass along a chain: run a workflow, follow the edge its outcome
    # takes, and save the routine run at every step, until a workflow ends
    # the call or an edge reaches :noop. The routine run closes on the value
    # that ends the pass.
    class Traversal
      # `save` keeps every routine run the pass produces, read tool and
      # write tool alike.
      def initialize(chain, ctx, routine_run, &save)
        @chain = chain
        @ctx = ctx
        @routine_run = routine_run
        @save = save
      end

      def call
        value = visit(@chain.entry)
        @save.call(@routine_run.close(value, @ctx.facts))
        value
      end

      private

      def visit(key)
        workflow = @chain.fetch(key)
        outcome = workflow.call(@ctx)
        outcome.is_a?(Symbol) ? follow(workflow, outcome) : outcome
      end

      def follow(workflow, outcome)
        from = workflow.key
        to = @chain.target(from, outcome)
        advance(from, to)
        (to == :noop) ? Finished.closing(workflow, outcome, @ctx) : visit(to)
      end

      def advance(from, to)
        @routine_run = @routine_run.advance(from, to)
        @save.call(@routine_run)
      end
    end
  end
end
