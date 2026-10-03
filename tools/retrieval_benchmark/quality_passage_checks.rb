# frozen_string_literal: true

require "json"

module Plastic
  module RetrievalBenchmark
    # Carries the only search-row fields needed to fetch one bounded passage.
    QualityPassageCandidate = Data.define(:uri, :position, :store) do
      def self.from(row) = new(row.fetch("uri"), row.fetch("position"), row.fetch("store"))

      def check(home:, hint:, rank:)
        passage = fetch(home)
        { "uri" => uri, "rank" => rank, "position" => position, "hint" => hint,
          "body" => passage&.fetch("body"), "matched" => passage&.fetch("body")&.include?(hint) || false }
      end

      private

      def fetch(home)
        argv = [File.join(RetrievalBenchmark::ROOT, "bin", "plastic"), "document", "get", uri, "--passage", position.to_s, "--json"]
        sample = Measurements.run_command({ home:, argv:, stores: [store] })
        document = JSON.parse(sample.fetch("stdout")).dig("result", "document")
        document if sample.fetch("exit_status").zero? && document
      end
    end

    # Fetches passages only for references named by a quality query.
    class QualityPassageChecks
      def initialize(home, expected)
        @home = home
        @expected = expected
      end

      def evaluate(rows)
        rows.filter_map.with_index do |row, index|
          candidate = QualityPassageCandidate.from(row)
          uri = candidate.uri
          candidate.check(home: @home, hint: @expected.fetch(uri), rank: index + 1) if @expected.key?(uri)
        end
      end
    end
  end
end
