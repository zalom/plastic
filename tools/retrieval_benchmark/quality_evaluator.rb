# frozen_string_literal: true

require "json"
require_relative "quality_seed"
require_relative "quality_query"

module Plastic
  module RetrievalBenchmark
    # Builds the public quality report from one candidate fixture and its answers.
    QualityEvaluationReport = Data.define(:candidate, :answers) do
      def build
        { "status" => candidate.fetch("status"), "owner_review" => { "status" => "pending" }, "synthetic_top_20" => answers,
          "synthetic_recall" => answers.count { |answer| answer.fetch("passed") }.fdiv(answers.length) }
      end
    end

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
        QualityEvaluationReport.new(candidate, answers).build
      end
    end
  end
end
