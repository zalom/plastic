# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "../../scripts/lib/plastic/graph/database/connection_pool"

module Plastic
  module RetrievalBenchmark
    class Concurrency
      def initialize(benchmark, samples)
        @benchmark = benchmark
        @samples = samples
      end

      def measure
        writer = start_writer
        readers = @samples.times.map { reader_sample }
        diagnostics = writer_diagnostics(writer)
        busy_failures = readers.count { |sample| busy_error?(sample) }
        diagnostics.merge(
          "reader_samples" => readers,
          "busy_handling" => busy_handling(busy_failures)
        )
      ensure
        close_streams(writer)
      end

      private

      def start_writer
        stdin, stdout, stderr, wait = Open3.popen3(worker_environment, RbConfig.ruby, worker_path, "writer", @benchmark.fetch(:home), @samples.to_s)
        stdin.close
        { stdin:, stdout:, stderr:, wait: }
      end

      def writer_diagnostics(writer)
        { "writer_exit_status" => writer.fetch(:wait).value.exitstatus,
          "writer_stdout" => writer.fetch(:stdout).read,
          "writer_stderr" => writer.fetch(:stderr).read }
      end

      def close_streams(writer)
        return unless writer

        writer.values_at(:stdin, :stdout, :stderr).each { |stream| stream.close unless stream.closed? }
      end

      def reader_sample
        sample = Measurements.run_command(@benchmark.fetch(:commands).fetch("exact_lookup"))
        sample["immutable_reference_consistent"] = sample.fetch("output_valid")
        sample
      end

      def worker_environment = Measurements.environment(@benchmark.fetch(:commands).fetch("exact_lookup"))

      def worker_path = File.join(RetrievalBenchmark::ROOT, "tools", "retrieval_benchmark", "worker.rb")

      def busy_handling(busy_failures)
        { "timeout_ms" => Graph::Database::Connection::BUSY_TIMEOUT, "busy_failures" => busy_failures,
          "status" => busy_failures.zero? ? "no_busy_errors" : "busy_errors" }
      end

      def busy_error?(sample) = sample.fetch("stderr").match?(/(?:busy|locked)/i)
    end
  end
end
