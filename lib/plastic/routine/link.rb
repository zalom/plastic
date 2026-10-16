# frozen_string_literal: true

require_relative "../facts"

module Plastic
  class Routine < CLI::Command
    # One link of a chain: a workflow key, its workflow class, and the edges
    # that leave it. It lists the wiring faults of that one workflow.
    class Link
      def initialize(chain, key)
        @chain = chain
        @key = key
        @workflow = chain.fetch(key)
      end

      # `declared` are every fact name the routine declares.
      def problems(declared)
        [*missing_edges, *stray_edges, *agent_not_last, *open_ends, *undeclared(declared), *@workflow.problems]
      end

      private

      def outcomes = @workflow.outcome_names

      def missing_edges
        (outcomes - [:handoff]).reject { |outcome| @chain.next_key(@key, outcome) }
          .map { |outcome| "#{@key} has no edge for #{outcome}" }
      end

      def stray_edges
        @chain.leaving(@key).select { |edge| edge.stray?(outcomes) }
          .map { |edge| "#{@key} has an edge for #{edge.on}, which it never returns" }
      end

      # An agent workflow hands over and the call ends, so nothing may follow
      # it but :noop.
      def agent_not_last
        return [] unless @workflow.lane == "agent" && @chain.successors(@key).any?

        ["#{@key} is an agent workflow and must end the chain"]
      end

      def open_ends
        outcomes.select { |outcome| ends_on?(outcome) && !@workflow.ending(outcome) }
          .map { |outcome| "#{@key} ends on #{outcome}, and no outcome line gives its because:" }
      end

      def ends_on?(outcome) = outcome == :handoff || @chain.next_key(@key, outcome) == :noop

      def undeclared(declared)
        names = @workflow.templates.flat_map { |template| Facts.names_in(template) }
        (names.uniq - declared).map { |name| "#{@key} prints %{#{name}}, which no one declares" }
      end
    end
  end
end
