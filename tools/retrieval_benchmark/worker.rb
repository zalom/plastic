# frozen_string_literal: true

require "json"
require "time"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

module Plastic
  module RetrievalBenchmark
    # Writes bounded revisions while benchmark readers measure overlap behavior.
    class Worker
      def initialize(arguments)
        @home, @samples, @ready, @start, @intent_id, @path = arguments
      end

      def run
        File.write(@ready, "ready")
        sleep 0.005 until File.exist?(@start)
        started_at = Time.now.utc.iso8601(6)
        write_revisions
        puts JSON.generate("started_at" => started_at, "finished_at" => Time.now.utc.iso8601(6))
      end

      private

      def write_revisions
        writer = Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
        (@samples.to_i * 10).times do |index|
          writer.write(@intent_id, @path, "concurrent writer revision #{index}")
          sleep 0.01
        end
      end

      def graphs = @graphs ||= Graph.open(home: @home, store: "store-1")
    end
  end
end

Plastic::RetrievalBenchmark::Worker.new(ARGV.drop(1)).run if $PROGRAM_NAME == __FILE__
