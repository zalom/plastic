# frozen_string_literal: true

require "time"

module Plastic
  module RetrievalBenchmark
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
        { "schema_version" => schema.fetch("schema_version"), "generated_at" => Time.now.utc.iso8601,
          "hardware" => hardware, "cache" => schema.dig("warmup_samples", "cache"), "warmup" => @warmup, "samples" => @samples,
          "corpus" => @corpus, "targets_ms" => targets, "measurements" => @measurements, "p95_ms" => durations,
          "acceptance_gates" => acceptance_gates(durations),
          "owner_review" => { "status" => "pending", "reason" => "Synthetic corpus measurements do not satisfy the owner-reviewed quality gate." } }
      end

      private

      def schema = RetrievalBenchmark.schema
      def hardware = { "ruby" => RUBY_DESCRIPTION, "platform" => RUBY_PLATFORM, "cpu" => `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip, "memory_bytes" => `sysctl -n hw.memsize 2>/dev/null`.strip }
      def targets = schema.fetch("warm_p95_targets_ms")
      def p95_measurements = @measurements.slice("exact_lookup", "single_store_top_20", "three_store_rrf_top_20").transform_values { |samples| p95(samples) }
      def p95(samples) = samples.map { |sample| sample.fetch("duration_ms") }.sort.fetch((samples.length * 0.95).ceil - 1)
      def acceptance_gates(durations) = { "latency" => durations.to_h { |id, duration| [id, gate(id, duration)] }, "owner_review" => { "status" => "pending" }, "intent_ready" => false }

      def gate(id, duration)
        target = targets.fetch(id)
        { "status" => gate_status(duration, target), "p95_ms" => duration, "target_ms" => target }
      end

      def gate_status(duration, target)
        return "passed" if duration <= target

        "missed"
      end
    end
  end
end
