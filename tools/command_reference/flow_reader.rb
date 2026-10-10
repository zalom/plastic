# frozen_string_literal: true

module CommandReference
  # Reads one workflow of a chain: its rows and its outcomes, each with the line that declares it.
  class FlowReader
    def initialize(source, chain)
      @source = source
      @chain = chain
    end

    def all = @chain.keys.map { |key| call(key) }

    def call(key) = WorkflowReading.new(@source, @chain, key).flow
  end
end
