# frozen_string_literal: true

require_relative "../workflow"

module Plastic
  class AgentWorkflow < Workflow
    # One thing the agent does, said in words. Its done: lambda reads the
    # graphs, so the next call sees whether the agent did it. words: says in words what the agent gets, for the page that explains a say: made of one placeholder.
    Step = Data.define(:name, :done, :say, :words) do
      def initialize(words: nil, **rest) = super

      def left?(ctx) = !done.call(ctx)

      def instruction(ctx) = ctx.fill(say)
    end
  end
end
