# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../clock"

module Plastic
  module Installations
    # The record of installs and updates: one JSON row for each, in
    # versions.json of the Plastic home.
    class Ledger
      def initialize(home, clock: Time)
        @path = File.join(home, "versions.json")
        @clock = clock
      end

      def append(version, action, harness: nil)
        row = { version:, action:, at: Plastic.timestamp(@clock.now) }
        row[:harness] = harness if harness
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, "#{JSON.generate(row)}\n", mode: "a")
      end

      def append_run(version, action, harnesses)
        harnesses.each { |harness| append(version, action, harness:) }
        append(version, action) if harnesses.empty?
      end

      def read
        return [] unless File.exist?(@path)

        File.readlines(@path).filter_map { |line| Ledger.parsed(line) }
      end

      def self.parsed(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      private
    end
  end
end
