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

      # One call of a workflow against the graphs of the global store, as a
      # routine makes it: the workflow's own facts plus the ones given.
      def run_workflow(flow, **facts)
        context = call_context(declared: flow.facts, **facts)
        [flow.call(context), context]
      end

      # The context of one call against the graphs of the global store.
      def call_context(declared: [], harness: scoped_harness, graphs: store_graphs, **facts)
        Plastic::Context.new(declared: (declared + facts.keys).uniq, facts:, graphs:, harness:)
      end

      # The labelled rows a call printed, as an output keeps them.
      Rows = Struct.new(:rows) do
        def raw(_text) = nil

        def row(label, value) = rows << [label, value]
      end

      def printed_rows(context) = Rows.new([]).tap { |output| context.print_to(output) }.rows

      def printed_row(context, label) = printed_rows(context).assoc(label)&.last

      # The session and store scope of a call made from the test's home.
      def scoped_harness(session: nil, slug: nil, env: {})
        scope = Plastic::CLI::Scope.new(env: { "PLASTIC_HOME" => @plastic_home }.merge(env), home: @home, slug:, directory: @home)
        Plastic::Context::Harness.new(session, scope)
      end
    end
  end
end
