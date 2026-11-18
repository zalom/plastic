# frozen_string_literal: true

require_relative "../workflow"
require_relative "../errors"

module Plastic
  class CodeWorkflow < Workflow
    # A step that changes state. Its done: lambda says whether the change is
    # in place, before the body and again after it.
    Step = Data.define(:name, :done, :changes, :body) do
      def done?(ctx) = done.call(ctx)

      def call(ctx, workflow)
        return if done?(ctx)

        body.call(ctx)
        confirm(ctx, workflow)
      end

      # The done check must hold after the body, or the step failed.
      def confirm(ctx, workflow)
        raise Failed.new("the step ran and its done check still fails", source: "#{workflow.key}, #{name}") unless done?(ctx)
      end
    end
  end
end
