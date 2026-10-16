# frozen_string_literal: true

require_relative "../invalid"
require_relative "../workflow"
require_relative "edge"
require_relative "branches"
require_relative "link"

module Plastic
  class Routine < CLI::Command
    # The chain of one routine as data: the workflow keys in the order the
    # class body names them, and the edges that say where each outcome goes.
    # `problems` lists every wiring fault, and Routine.verify raises them.
    class Chain
      attr_reader :keys, :edges

      def initialize(owner)
        @owner = owner
        @keys = []
        @edges = []
      end

      # The plain next: goes in after the on lines, so the first edge that
      # carries an outcome is the one it takes: an on line wins.
      def add(key, to = nil, &branches)
        keys << key
        Branches.new(self, key).instance_eval(&branches) if branches
        edge(key, nil, to) if to
      end

      def edge(from, on, to) = edges << Edge.new(from, on, to)

      def entry = keys.first

      # The workflow class for a key, from the namespace the routine names.
      def fetch(key) = Workflow.fetch(key, from: @owner.workflows)

      def facts = keys.flat_map { |key| fetch(key).facts }

      # Where `outcome` of `key` goes, raising when no edge carries it.
      def target(key, outcome)
        next_key(key, outcome) or raise Invalid, "#{@owner}: #{key} has no edge for #{outcome}"
      end

      # Where `outcome` of `key` goes, or nil when no edge carries it.
      def next_key(key, outcome) = leaving(key).find { |edge| edge.carries?(outcome) }&.to

      def leaving(key) = edges.select { |edge| edge.from == key }

      def successors(key) = leaving(key).map(&:to) - [:noop]

      # `given` are the tool's arguments and options; the chain adds the facts
      # its workflows set.
      def problems(given)
        declared = given + facts
        edge_problems + unreachable + link_problems(declared)
      rescue Invalid => error
        [error.message]
      end

      private

      def edge_problems = edges.filter_map { |edge| edge.problem(keys) }

      def link_problems(declared) = keys.flat_map { |key| Link.new(self, key).problems(declared) }

      def unreachable
        seen = reachable([entry])
        (keys - seen).map { |key| "#{key} cannot be reached from #{entry}" }
      end

      # Every key the chain reaches from `seen`, breadth first.
      def reachable(seen)
        found = seen.flat_map { |key| successors(key) }.uniq - seen
        found.empty? ? seen : reachable(seen + found)
      end
    end
  end
end
