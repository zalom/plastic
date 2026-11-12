# frozen_string_literal: true

require_relative "../workflow"

module Plastic
  class AgentWorkflow < Workflow
    # One thing the agent does, said in words. Its done: lambda reads the
    # graphs, so the next call sees whether the agent did it.
    Step = Data.define(:name, :done, :say) do
      def left?(ctx) = !done.call(ctx)

      def instruction(ctx) = ctx.fill(say)
    end
  end
end
