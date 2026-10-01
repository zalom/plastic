# frozen_string_literal: true

module Plastic
  class TestCase
    # Builders for the workflow tests: a context and anonymous workflow classes.
    module WorkflowHelper
      Flows = Fixtures::Workflows

      def context(declared: %i[name mode], facts: { name: "ada" })
        Plastic::Context.new(declared:, facts:, graphs: {})
      end

      def code(&body) = Class.new(Plastic::CodeWorkflow, &body)

      def agent(&body) = Class.new(Plastic::AgentWorkflow, &body)
    end
  end
end
