# frozen_string_literal: true

require "json"
require_relative "quality_seed"
require_relative "quality_query"

module Plastic
  module RetrievalBenchmark
    # Evaluates each public retrieval query against its expected evidence hint.
    class QualityEvaluator
      def initialize(input, directory)
        @input = input
        @home = File.join(directory, "quality-home")
      end

      def evaluate
        candidate = JSON.parse(File.read(@input))
        QualitySeed.new(@home).seed(candidate.fetch("documents"))
        answers = candidate.fetch("queries").map { |query| QualityQuery.new(@home, query).evaluate }
        report(candidate, answers)
      end

      private

      def report(candidate, answers)
        { "status" => candidate.fetch("status"), "owner_review" => { "status" => "pending" }, "synthetic_top_20" => answers,
          "synthetic_recall" => answers.count { |answer| answer.fetch("passed") }.fdiv(answers.length) }
      end
    end
  end
end
