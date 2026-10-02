# frozen_string_literal: true

require "json"
require_relative "retrieval_benchmark/corpus"
require_relative "retrieval_benchmark/runner"
require_relative "retrieval_benchmark/quality_evaluator"

module Plastic
  # Builds public text corpora and measures the shipped retrieval commands.
  module RetrievalBenchmark
    ROOT = File.expand_path("..", __dir__)
    SCHEMA_PATH = File.join(__dir__, "retrieval_benchmark_schema.json")

    module_function

    def schema = JSON.parse(File.read(SCHEMA_PATH))

    def generate_corpus(directory, target_bytes:, stores: 3)
      Corpus.new(directory, target_bytes, stores).generate
    end

    def run(output:, corpus_bytes: 15_000_000, warmup: schema.dig("warmup_samples", "warmup"), samples: schema.dig("warmup_samples", "samples"), quality_input: nil)
      Runner.new(output:, corpus_bytes:, warmup:, samples:, quality_input:).run
    end
  end
end
