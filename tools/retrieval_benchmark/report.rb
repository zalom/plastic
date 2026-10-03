# frozen_string_literal: true

require "time"

module Plastic
  module RetrievalBenchmark
    # Reads schema-backed report constants and projects local hardware facts.
    BenchmarkReportEnvironment = Data.define(:schema, :ruby_description, :platform, :cpu, :memory_bytes) do
      def hardware
        { "ruby" => ruby_description, "platform" => platform, "cpu" => cpu, "memory_bytes" => memory_bytes }
      end

      def targets = schema.fetch("warm_p95_targets_ms")
    end

    # Computes the declared warm percentile from one command's samples.
    BenchmarkPercentile = Data.define(:samples) do
      def warm_p95_ms
        sorted_durations.fetch((sorted_durations.length * 0.95).ceil - 1)
      end

      private

      def sorted_durations = samples.map { |sample| sample.fetch("duration_ms") }.sort
    end

    # Compares one measured duration to its declared target.
    BenchmarkAcceptanceGate = Data.define(:duration, :target) do
      def build
        status = (duration <= target) ? "passed" : "missed"
        { "status" => status, "p95_ms" => duration, "target_ms" => target }
      end
    end

    # Builds benchmark evidence and keeps open acceptance gates explicit.
    class Report
      def initialize(corpus, measurements, warmup, samples)
        @corpus = corpus
        @measurements = measurements
        @warmup = warmup
        @samples = samples
      end

      def build
        durations = p95_measurements
        schema = environment.schema
        { "schema_version" => schema.fetch("schema_version"), "generated_at" => Time.now.utc.iso8601,
          "hardware" => environment.hardware, "cache" => schema.dig("warmup_samples", "cache"), "warmup" => @warmup, "samples" => @samples,
          "corpus" => @corpus, "targets_ms" => environment.targets, "measurements" => @measurements, "p95_ms" => durations,
          "acceptance_gates" => acceptance_gates(durations),
          "owner_review" => { "status" => "pending", "reason" => "Synthetic corpus measurements do not satisfy the owner-reviewed quality gate." } }
      end

      private

      def environment = (@environment ||= BenchmarkReportEnvironment.new(RetrievalBenchmark.schema, RUBY_DESCRIPTION, RUBY_PLATFORM, `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip, `sysctl -n hw.memsize 2>/dev/null`.strip))
      def p95_measurements = @measurements.slice("exact_lookup", "single_store_top_20", "three_store_rrf_top_20").transform_values { |samples| BenchmarkPercentile.new(samples).warm_p95_ms }
      def acceptance_gates(durations) = { "latency" => durations.to_h { |id, duration| [id, BenchmarkAcceptanceGate.new(duration, environment.targets.fetch(id)).build] }, "owner_review" => { "status" => "pending" }, "intent_ready" => false }
    end
  end
end
