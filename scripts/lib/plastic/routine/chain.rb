# frozen_string_literal: true

require_relative "../invalid"
require_relative "../workflow"

module Plastic
  class Routine < CLI::Command
    # The chain of one routine as data: the workflow keys in the order the
    # class body names them, and the edges that say where each outcome goes.
    # `problems` lists every wiring fault, and Routine.verify! raises them.
    class Chain
      Edge = Data.define(:from, :on, :to)

      # The block form of `workflow`: one `on` line per outcome.
      class Branches
        def initialize(chain, key)
          @chain = chain
          @key = key
        end

        def on(outcome, **edge) = @chain.edge(@key, outcome, edge.fetch(:next))
      end

      attr_reader :keys, :edges

      def initialize(owner)
        @owner = owner
        @keys = []
        @edges = []
      end

      def add(key, to = nil, &branches)
        keys << key
        edge(key, nil, to) if to
        Branches.new(self, key).instance_eval(&branches) if branches
      end

      def edge(from, on, to) = edges << Edge.new(from, on, to)

      def entry = keys.first

      # The workflow class for a key, from the namespace the routine names.
      def fetch(key) = Workflow.fetch(key, from: @owner.workflows)

      def facts = keys.flat_map { |key| fetch(key).facts }

      # Where `outcome` of `key` goes. An `on` line wins over a plain next:.
      def target(key, outcome)
        edge_to(key, outcome) or raise Invalid, "#{@owner}: #{key} has no edge for #{outcome}"
      end

      def edge_to(key, outcome)
        from = edges.select { |e| e.from == key }
        (from.find { |e| e.on == outcome } || from.find { |e| e.on.nil? })&.to
      end

      # `given` are the tool's arguments and options; the chain adds the facts
      # its workflows set.
      def problems(given)
        workflows = keys.to_h { |key| [key, fetch(key)] }
        [unknown_targets, backward_edges, unreachable, *workflow_problems(workflows, given + facts)].flatten
      rescue Invalid => e
        [e.message]
      end

      private

      def workflow_problems(workflows, declared)
        [missing_edges(workflows), extra_edges(workflows), agents_not_last(workflows), open_ends(workflows),
          undeclared(workflows, declared), workflows.values.flat_map(&:problems)]
      end

      def successors(key) = edges.select { |e| e.from == key }.map(&:to) - [:noop]

      def unknown_targets
        (edges.map(&:to) - keys - [:noop]).map { |to| "#{to} is a target but not in the chain" }
      end

      # Every edge points to a later key, so a chain can only move forward
      # and never loops.
      def backward_edges
        edges.select { |e| keys.include?(e.to) && keys.index(e.to) <= keys.index(e.from) }
          .map { |e| "#{e.from} -> #{e.to} points backward; a chain only moves forward" }
      end

      def unreachable
        seen = [entry]
        queue = [entry]
        while (key = queue.shift)
          (successors(key) - seen).each do |nxt|
            seen << nxt
            queue << nxt
          end
        end
        (keys - seen).map { |key| "#{key} cannot be reached from #{entry}" }
      end

      def missing_edges(workflows)
        workflows.flat_map do |key, workflow|
          (workflow.outcome_names - [:handoff]).reject { |o| edge_to(key, o) }
            .map { |o| "#{key} has no edge for #{o}" }
        end
      end

      def extra_edges(workflows)
        edges.reject { |e| e.on.nil? || workflows.fetch(e.from).outcome_names.include?(e.on) }
          .map { |e| "#{e.from} has an edge for #{e.on}, which it never returns" }
      end

      # An agent workflow hands over and the call ends, so nothing may follow
      # it but :noop.
      def agents_not_last(workflows)
        workflows.select { |_key, w| w.lane == "agent" }.filter_map do |key, _w|
          "#{key} is an agent workflow and must end the chain" if successors(key).any?
        end
      end

      def open_ends(workflows)
        workflows.flat_map do |key, workflow|
          ending = workflow.outcome_names.select { |o| o == :handoff || edge_to(key, o) == :noop }
          ending.reject { |o| workflow.outcome_for(o)&.because }
            .map { |o| "#{key} ends on #{o}, and no outcome line gives its because:" }
        end
      end

      def undeclared(workflows, declared)
        workflows.flat_map do |key, workflow|
          names = workflow.templates.flat_map { |t| t.scan(/%\{(\w+)\}/).flatten.map(&:to_sym) }
          (names.uniq - declared).map { |name| "#{key} prints %{#{name}}, which no one declares" }
        end
      end
    end
  end
end
