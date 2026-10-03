# frozen_string_literal: true

require "json"

module Plastic
  module RetrievalBenchmark
    # Fetches passages only for references named by a quality query.
    class QualityPassageChecks
      def initialize(home, expected)
        @home = home
        @expected = expected
      end

      def evaluate(rows)
        rows.filter_map.with_index do |row, index|
          check(row, index + 1) if @expected.key?(row.fetch("uri"))
        end
      end

      private

      def check(row, rank)
        passage = fetch(row)
        hint = @expected.fetch(row.fetch("uri"))
        { "uri" => row.fetch("uri"), "rank" => rank, "position" => row.fetch("position"), "hint" => hint,
          "body" => passage&.fetch("body"), "matched" => passage&.fetch("body")&.include?(hint) || false }
      end

      def fetch(row)
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "document", "get", row.fetch("uri"), "--passage", row.fetch("position").to_s, "--json"]
        sample = Measurements.run_command({ home: @home, argv:, stores: [row.fetch("store")] })
        document = JSON.parse(sample.fetch("stdout")).dig("result", "document")
        document if sample.fetch("exit_status").zero? && document
      end
    end
  end
end
