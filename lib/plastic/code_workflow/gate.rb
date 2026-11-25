# frozen_string_literal: true

require_relative "../workflow"
require_relative "../errors"

module Plastic
  class CodeWorkflow < Workflow
    # A check that stops the call unless its pass: lambda holds. It prints
    # its reason as a refusal, exit 3, or as a failure, exit 1.
    Gate = Data.define(:reason, :stops, :pass, :offers, :because, :words) do
      def initialize(words: nil, **rest) = super

      def name = "gate"

      def templates = [reason, offers, because].compact

      def call(ctx, workflow)
        return if pass.call(ctx)

        next_command, why = [offers, because].map { |template| template && ctx.fill(template) }
        raise stop.new(ctx.fill(reason), next_command:, because: why, source: "#{workflow.key}, #{name}")
      end

      def stop = (stops == :refusal) ? Refused : Failed
    end
  end
end
