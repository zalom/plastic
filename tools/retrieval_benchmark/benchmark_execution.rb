# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require_relative "seeder"
require_relative "measurements"
require_relative "report"
require_relative "quality_evaluator"

module Plastic
  module RetrievalBenchmark
    # Coordinates corpus setup, measurement, quality, and report persistence.
    class BenchmarkExecution
      def initialize(options) = @options = options

      def run = Dir.mktmpdir("plastic-retrieval-benchmark") { |directory| run_in(directory) }

      private

      def run_in(directory)
        corpus, benchmark = prepare_benchmark(directory)
        report = measured_report(corpus, benchmark)
        attach_quality(report, directory)
        write(report)
        report
      end

      def prepare_benchmark(directory)
        corpus = RetrievalBenchmark.generate_corpus(File.join(directory, "corpus"), target_bytes: @options.fetch(:corpus_bytes))
        [corpus, Seeder.new(directory, corpus).seed]
      end

      def measured_report(corpus, benchmark)
        Report.new(corpus, measure(benchmark), @options.fetch(:warmup), @options.fetch(:samples)).build
      end

      def attach_quality(report, directory)
        report["quality"] = quality(directory) if @options.fetch(:quality_input)
      end

      def measure(benchmark) = Measurements.new(benchmark, @options.fetch(:warmup), @options.fetch(:samples)).measure

      def quality(directory)
        QualityEvaluator.new(@options.fetch(:quality_input), directory).evaluate
      rescue KeyError, JSON::ParserError => error
        { "status" => "error", "owner_review" => { "status" => "pending" }, "error" => error.message }
      end

      def write(report)
        path = File.expand_path(@options.fetch(:output))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(report) + "\n")
      end
    end
  end
end
