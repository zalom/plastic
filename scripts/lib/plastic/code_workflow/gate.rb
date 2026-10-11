# frozen_string_literal: true

require_relative "../workflow"
require_relative "../failed"
require_relative "../refused"

module Plastic
  class CodeWorkflow < Workflow
    # A check that stops the call unless its pass: lambda holds. It prints
    # its reason as a refusal, exit 3, or as a failure, exit 1.
    Gate = Data.define(:reason, :stops, :pass, :offers, :because) do
      def name = "gate"

      def templates = [reason, offers, because].compact

      # Nil when the gate lets the call through; otherwise the value that ends it.
      def run(ctx, workflow)
        return if pass.call(ctx)

        ending(workflow.key, ctx.fill(reason), [offers, because].map { |template| template && ctx.fill(template) })
      end

      def ending(key, message, lines)
        (stops == :refusal) ? Refused.new(key, message, *lines) : Failed.new(key, name, message, *lines)
      end
    end
  end
end
