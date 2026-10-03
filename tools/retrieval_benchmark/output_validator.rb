# frozen_string_literal: true

require "json"

module Plastic
  module RetrievalBenchmark
    # Checks that a timed command returned evidence from its selected stores.
    class OutputValidator
      def self.valid?(command, stdout, status)
        return false unless status.success?

        result = JSON.parse(stdout).fetch("result")
        command[:reference] ? exact_match?(command, result) : selected_store_match?(command, result)
      rescue JSON::ParserError, KeyError
        false
      end

      def self.exact_match?(command, result) = result.fetch("document").fetch("uri") == command.fetch(:reference).fetch(:uri)

      def self.selected_store_match?(command, result)
        returned = result.fetch("results").map { |row| row.fetch("store") }.uniq
        returned.any? && (returned - command.fetch(:stores)).empty?
      end
    end
  end
end
