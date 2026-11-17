# frozen_string_literal: true

require_relative "../finished"

module Plastic
  class Routine < CLI::Command
    # One pass along a chain: run a workflow, follow the edge its outcome
    # takes, and save the command run at every step, until a workflow ends
    # the call or an edge reaches :noop. The command run closes on the value
    # that ends the pass.
    class Traversal
      # `save` keeps every command run the pass produces, read tool and
      # write tool alike.
      def initialize(chain, ctx, command_run, &save)
        @chain = chain
        @ctx = ctx
        @command_run = command_run
        @save = save
      end

      def call
        value = visit(@chain.entry)
        keep(value)
        printed = yield(value)
        keep(printed) unless printed.equal?(value)
        printed
      rescue Failed, Refused => error
        keep(error)
        raise
      end

      private

      def keep(value) = @save.call(@command_run.close(value, @ctx.facts))

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
        @command_run = @command_run.advance(from, to)
        @save.call(@command_run)
      end
    end
  end
end
