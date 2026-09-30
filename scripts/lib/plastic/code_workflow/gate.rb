# frozen_string_literal: true

require_relative "../workflow"
require_relative "../failed"
require_relative "../refused"

module Plastic
  class CodeWorkflow < Workflow
    # A check that stops the call unless its pass: lambda holds. It prints
    # its reason as a refusal, exit 3, or as a failure, exit 1.
    Gate = Data.define(:reason, :stops, :pass) do
      def name = "gate"

      # Nil when the gate lets the call through; otherwise the value that ends it.
      def run(ctx, workflow)
        return if pass.call(ctx)

        ending(workflow.key, ctx.fill(reason))
      end

      def ending(key, message) = (stops == :refusal) ? Refused.new(key, message) : Failed.new(key, name, message)
    end
  end
end
