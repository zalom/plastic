# frozen_string_literal: true

require "json"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    class Concurrency
      def initialize(benchmark, samples)
        @benchmark = benchmark
        @samples = samples
      end

      def measure
        writer = start_writer
        readers = reader_samples
        busy_failures = readers.select { |sample| busy_error?(sample) }
        { "writer_exit_status" => wait_for_writer(writer), "reader_samples" => readers,
          "busy_handling" => { "timeout_ms" => Graph::Database::Connection::BUSY_TIMEOUT, "busy_failures" => busy_failures.length,
                               "status" => busy_failures.empty? ? "no_busy_errors" : "busy_errors" } }
      end

      private

      def reader_samples
        processes = @samples.times.map { spawn_reader }
        processes.map { |reader, process| read_sample(reader, process) }
      end

      def spawn_reader
        reader, writer = IO.pipe
        process = fork do
          reader.close
          sample = Measurements.run_command(@benchmark.fetch(:commands).fetch("exact_lookup"))
          sample["immutable_reference_consistent"] = sample.fetch("output_valid")
          writer.write(JSON.generate(sample))
          writer.close
          exit! 0
        end
        writer.close
        [reader, process]
      end

      def read_sample(reader, process)
        JSON.parse(reader.read)
      ensure
        reader.close unless reader.closed?
        Process.wait(process)
      end

      def start_writer = fork { write_revisions }

      def wait_for_writer(process) = Process.wait2(process).last.exitstatus

      def write_revisions
        Graph::Database::ConnectionPool.disconnect
        graphs = Graph.open(home: @benchmark.fetch(:home), store: "store-1")
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        @samples.times { |index| writer.write("concurrent", "writer.md", "concurrent writer revision #{index}") }
        exit! 0
      rescue SQLite3::Exception
        exit! 1
      end

      def busy_error?(sample) = sample.fetch("stderr").match?(/(?:busy|locked)/i)
    end
  end
end
