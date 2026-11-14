# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../clock"

module Plastic
  module Installations
    # The record of installs and updates: one JSON row for each, in
    # versions.json of the Plastic home.
    class Ledger
      def initialize(home)
        @path = File.join(home, "versions.json")
      end

      def append(version, action, harness: nil)
        row = { version:, action:, at: Plastic.now }
        row[:harness] = harness if harness
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, "#{JSON.generate(row)}\n", mode: "a")
      end

      def read
        return [] unless File.exist?(@path)

        File.readlines(@path).filter_map { |line| parsed(line) }
      end

      private

      def parsed(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
