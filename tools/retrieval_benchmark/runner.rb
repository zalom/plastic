# frozen_string_literal: true

require_relative "benchmark_execution"

module Plastic
  module RetrievalBenchmark
    # Starts an isolated retrieval benchmark run.
    class Runner
      def initialize(output:, corpus_bytes:, warmup:, samples:, quality_input:)
        @options = { output:, corpus_bytes:, warmup:, samples:, quality_input: }
      end

      def run = BenchmarkExecution.new(@options).run
    end
  end
end
