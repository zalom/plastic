# frozen_string_literal: true

require_relative "invalid"
require_relative "workflow/outcome"
require_relative "workflow/key"
require_relative "workflows/registry"

module Plastic
  # One named piece of a routine: steps that run in order, then outcome lines
  # that say how it ends. Two kinds share every word:
  #
  #   CodeWorkflow   Ruby steps that read and write the graphs
  #   AgentWorkflow  plain-word steps the agent does, checked on the next call
  #
  # A workflow's key is its lane plus its snake name: CloseIntent, a
  # CodeWorkflow, is :code_close_intent in workflows/close_intent.rb.
  # Workflows::REGISTRY lists every key, and `fetch` loads a file only when a
  # routine asks for its key.
  #
  # The class body is the definition. Each call runs on a new instance, so
  # nothing one call finds outlives it.
  class Workflow
    class << self
      def key = :"#{lane}_#{Plastic.snake(name.split("::").last)}"

      def lane = raise(NoMethodError, "#{name} must subclass CodeWorkflow or AgentWorkflow")

      # The workflow class for a key, from a namespace that holds a REGISTRY
      # and the classes.
      def fetch(key, from: Workflows)
        raise Invalid, "no workflow #{key} in #{from}::REGISTRY" unless from::REGISTRY.include?(key)

        Key.parse(key).workflow_in(from)
      end

      # The facts this workflow sets. The routine declares them on the context.
      def sets(*names) = facts.concat(names)

      def facts = (@facts ||= [])

      # One way the workflow ends. `offers:` is the command next: prints and
      # `because:` the line that says why; both matter only when the outcome
      # ends the chain. Each lane adds its own rules.
      def outcome(outcome_name, **options)
        unknown = options.keys - %i[if offers because stops]
        raise Invalid, "#{name}: outcome #{outcome_name} does not take #{unknown.join(", ")}" if unknown.any?

        outcomes << Outcome.new(outcome_name, *options.values_at(:if, :offers, :because, :stops))
      end

      def outcomes = (@outcomes ||= [])

      # The outcome line that can end the chain on `outcome_name`: the one that
      # gives its because: line. Nil when no line does.
      def ending(outcome_name) = outcomes.select(&:because).find { |outcome| outcome.name == outcome_name }

      # The next: and because: lines for an outcome that ends the chain.
      def closing(outcome_name, ctx)
        found = ending(outcome_name)
        raise Invalid, "#{key} ends on #{outcome_name}, and no outcome line gives its because:" unless found

        found.closing(ctx)
      end

      # Every %{name} this workflow prints. Routine.verify checks them.
      def templates = outcomes.flat_map(&:templates)

      # Wiring faults a class body cannot see until it has loaded.
      def problems = []

      def call(ctx) = new(ctx).call
    end

    def initialize(ctx)
      @ctx = ctx
    end

    # Returns an outcome's name, or the value that ends the call.
    def call
      raise NoMethodError, "#{self.class} must define call"
    end

    private

    attr_reader :ctx

    def key = self.class.key
  end
end
