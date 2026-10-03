# frozen_string_literal: true

require "json"
require "time"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    # Parses the writer arguments once and carries the named values together.
    BenchmarkWorkerArguments = Data.define(:home, :samples, :ready, :start, :intent_id, :path) do
      def self.parse(arguments) = new(*arguments)

      def revision_count = samples.to_i * 10
    end

    # Captures a single UTC timestamp for each event in the worker report.
    class BenchmarkWorkerClock
      def initialize(now: Time) = @now = now

      def timestamp = @now.now.utc.iso8601(6)
    end

    # Owns process-entrypoint state so loading the worker cannot start it.
    BenchmarkWorkerEntrypoint = Data.define(:arguments, :program_name, :file_name) do
      def run? = program_name == file_name

      def worker_arguments = arguments.drop(1)
    end

    # Writes bounded revisions while benchmark readers measure overlap behavior.
    class Worker
      def initialize(arguments, clock: BenchmarkWorkerClock.new)
        @arguments = BenchmarkWorkerArguments.parse(arguments)
        @clock = clock
      end

      def run
        mark_ready
        await_barrier
        started_at = @clock.timestamp
        write_revisions
        report(started_at)
      end

      def self.run_entrypoint(arguments:, program_name:, file_name:)
        entrypoint = BenchmarkWorkerEntrypoint.new(arguments, program_name, file_name)
        return unless entrypoint.run?

        new(entrypoint.worker_arguments).run
      end

      private

      def mark_ready = File.write(@arguments.ready, "ready")

      def await_barrier
        sleep 0.005 until File.exist?(@arguments.start)
      end

      def write_revisions
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        @arguments.revision_count.times do |index|
          writer.write(@arguments.intent_id, @arguments.path, "concurrent writer revision #{index}")
          sleep 0.01
        end
      end

      def report(started_at)
        puts JSON.generate("started_at" => started_at, "finished_at" => @clock.timestamp)
      end

      def graphs = @graphs ||= Graph.open(home: @arguments.home, store: "store-1")
    end
  end
end

Plastic::RetrievalBenchmark::Worker.run_entrypoint(arguments: ARGV, program_name: $PROGRAM_NAME, file_name: __FILE__)
