# frozen_string_literal: true

require_relative "invalid"
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
    # One way the workflow ends: the outcome's name, the check that picks it,
    # the command next: prints, the line because: prints, and how it stops.
    Outcome = Data.define(:name, :check, :offers, :because, :stops)

    class << self
      def key
        snake = name.split("::").last.gsub(/(?<=[a-z0-9])(?=[A-Z])/, "_").downcase
        :"#{lane}_#{snake}"
      end

      def lane = raise(NoMethodError, "#{name} must subclass CodeWorkflow or AgentWorkflow")

      # The workflow class for a key, from a namespace that holds a REGISTRY
      # and the classes. The key's lane must match the class.
      def fetch(key, from: Workflows)
        raise Invalid, "no workflow #{key} in #{from}::REGISTRY" unless from::REGISTRY.include?(key)

        lane, snake = key.to_s.split("_", 2)
        klass = workflow_class(from, snake)
        raise Invalid, "#{key} names a #{lane} workflow, and #{klass} is a #{klass.lane} workflow" unless klass.lane == lane

        klass
      end

      # The facts this workflow sets. The routine declares them on the context.
      def sets(*names) = facts.concat(names)

      def facts = (@facts ||= [])

      # One way the workflow ends. `offers:` is the command next: prints and
      # `because:` the line that says why; both matter only when the outcome
      # ends the chain. Each lane adds its own rules.
      def outcome(name, **options)
        unknown = options.keys - %i[if offers because stops]
        raise Invalid, "#{self.name}: outcome #{name} does not take #{unknown.join(", ")}" if unknown.any?

        outcomes << Outcome.new(name, options[:if], options[:offers], options[:because], options[:stops])
      end

      def outcomes = (@outcomes ||= [])

      def outcome_for(name) = outcomes.find { |o| o.name == name }

      # The next: and because: lines for an outcome that ends the chain.
      def closing(name, ctx)
        found = outcome_for(name)
        raise Invalid, "#{key} ends on #{name}, and no outcome line gives its because:" unless found&.because

        [found.offers ? ctx.fill(found.offers) : "none", ctx.fill(found.because)]
      end

      # Every %{name} this workflow prints. Routine.verify! checks them.
      def templates = outcomes.flat_map { |o| [o.offers, o.because] }.compact

      # Wiring faults a class body cannot see until it has loaded.
      def problems = []

      def call(ctx) = new(ctx).call

      private

      # A class already loaded is used as it is; any other is required from
      # workflows/ first.
      def workflow_class(from, snake)
        name = snake.split("_").map(&:capitalize).join
        require_relative "workflows/#{snake}" unless from.const_defined?(name, false)
        from.const_get(name, false)
      end
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
