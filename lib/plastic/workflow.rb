# frozen_string_literal: true

require_relative "invalid"
require_relative "workflow/outcome"
require_relative "workflow/key"
require_relative "workflow/declarations"

module Plastic
  # One named piece of a routine: steps that run in order, then outcome lines
  # that say how it ends. Two kinds share every word:
  #
  #   CodeWorkflow   Ruby steps that read and write the graphs
  #   AgentWorkflow  plain-word steps the agent does, checked on the next call
  #
  # A workflow's key is its lane plus the words of its job, and it never
  # changes. Workflows::REGISTRY maps every key to the class path of its
  # workflow: :code_close_intent is Workflows::Code::Intent::End, in
  # workflows/code/intent/end.rb. `fetch` loads a file only when a routine
  # asks for its key.
  #
  # The class body is the definition. Each call runs on a new instance, so
  # nothing one call finds outlives it.
  class Workflow
    extend Declarations

    class << self
      # The key that the REGISTRY of this class's namespace maps to its class path.
      def key
        namespace, path = home
        namespace::REGISTRY.key(path) || raise(Invalid, "#{name} is not in #{namespace}::REGISTRY")
      end

      # The namespace that holds this class's REGISTRY, and the class path under it.
      def home
        parts = name.split("::")
        parts.each_index do |index|
          count = index + 1
          namespace = Object.const_get(parts.first(count).join("::"))
          return [namespace, parts.drop(count).join("::")] if namespace.const_defined?(:REGISTRY, false)
        end
        raise Invalid, "#{name} sits in no namespace that holds a REGISTRY"
      end

      def lane = raise(NoMethodError, "#{name} must subclass CodeWorkflow or AgentWorkflow")

      # The workflow class for a key, from a namespace that holds a REGISTRY
      # and the classes.
      def fetch(key, from:)
        path = from::REGISTRY.fetch(key) { raise Invalid, "no workflow #{key} in #{from}::REGISTRY" }

        Key.parse(key, path).workflow_in(from)
      end

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
