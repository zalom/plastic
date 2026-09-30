# frozen_string_literal: true

require_relative "../workflow"
require_relative "../failed"

module Plastic
  class CodeWorkflow < Workflow
    # A step that changes state. Its done: lambda says whether the change is
    # in place, before the body and again after it.
    Step = Data.define(:name, :done, :body) do
      def done?(ctx) = done.call(ctx)

      # Nil when the change is in place; a Failed when the body ran and the
      # done check still fails.
      def run(ctx, workflow)
        return if done?(ctx)

        body.call(ctx)
        confirm(ctx, workflow)
      end

      # The done check must hold after the body, or the step failed.
      def confirm(ctx, workflow)
        Failed.new(workflow.key, name, "the step ran and its done check still fails") unless done?(ctx)
      end
    end
  end
end
