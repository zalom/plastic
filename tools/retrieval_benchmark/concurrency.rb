# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../../scripts/lib/plastic/graph/database/connection_pool"

module Plastic
  module RetrievalBenchmark
    # Measures reads while a writer updates a document in the same store.
    class Concurrency
      def initialize(benchmark, samples)
        @benchmark = benchmark
        @samples = samples
      end

      def measure
        Dir.mktmpdir("plastic-retrieval-concurrency") { |directory| measure_in(directory) }
      end

      private

      def measure_in(directory)
        writer = start_writer(directory)
        wait_for_ready(directory)
        File.write(start_path(directory), "start")
        readers = @samples.times.map { reader_sample }
        diagnostics = writer_diagnostics(writer)
        diagnostics.merge("reader_samples" => readers, "busy_handling" => busy_handling(readers),
          "overlap" => overlaps?(diagnostics, readers))
      ensure
        close_streams(writer)
      end

      def start_writer(directory)
        reference = @benchmark.fetch(:reference)
        stdin, stdout, stderr, wait = Open3.popen3(worker_environment, RbConfig.ruby, worker_path, "writer", @benchmark.fetch(:home), @samples.to_s, ready_path(directory), start_path(directory), reference.fetch(:intent_id), reference.fetch(:path))
        stdin.close
        { stdin:, stdout:, stderr:, wait: }
      end

      def ready_path(directory) = File.join(directory, "ready")

      def start_path(directory) = File.join(directory, "start")

      def wait_for_ready(directory)
        sleep 0.005 until File.exist?(ready_path(directory))
      end

      def writer_diagnostics(writer)
        report = JSON.parse(writer.fetch(:stdout).read)
        report.merge("writer_exit_status" => writer.fetch(:wait).value.exitstatus,
          "writer_stderr" => writer.fetch(:stderr).read)
      end

      def close_streams(writer)
        return unless writer

        writer.values_at(:stdin, :stdout, :stderr).each { |stream| stream.close unless stream.closed? }
      end

      def reader_sample
        sample = Measurements.run_command(@benchmark.fetch(:commands).fetch("exact_lookup"))
        document = JSON.parse(sample.fetch("stdout")).dig("result", "document")
        sample["immutable_reference_consistent"] = sample.fetch("output_valid") && document.fetch("revision") == Digest::SHA256.hexdigest(document.fetch("body"))
        sample
      end

      def worker_environment = Measurements.environment(@benchmark.fetch(:commands).fetch("exact_lookup"))

      def worker_path = File.join(RetrievalBenchmark::ROOT, "tools", "retrieval_benchmark", "worker.rb")

      def busy_handling(readers)
        busy_failures = readers.count { |sample| busy_error?(sample) }
        { "timeout_ms" => Graph::Database::Connection::BUSY_TIMEOUT, "busy_failures" => busy_failures,
          "status" => busy_failures.zero? ? "no_busy_errors" : "busy_errors" }
      end

      def overlaps?(diagnostics, readers)
        readers.any? { |sample| sample.fetch("started_at") < diagnostics.fetch("finished_at") }
      end

      def busy_error?(sample) = sample.fetch("stderr").match?(/(?:busy|locked)/i)
    end
  end
end
