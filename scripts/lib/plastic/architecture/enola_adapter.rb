# frozen_string_literal: true

module Plastic
  module Architecture
    # Reads Enola facts without allowing retrieval to generate an index.
    class EnolaAdapter
      VERSION = "0.4.18"
      ARCHIVE_SHA256 = "d31f197bb86ea1eebaa2caa2434e039bf47516daad5455ca400bcfd37923f837"
      BINARY_SHA256 = "9f04b4637e22eac056a85959b20ec68ebe7311b42c20e2b02bd5dfe50edb0f21"

      def initialize(executor: method(:execute))
        @executor = executor
      end

      def receipt(binary_sha256:, archive_sha256:)
        output, error, available = @executor.call("enola", "--version")
        version = output.to_s[/\d+\.\d+\.\d+/]
        { "provider" => "enola", "available" => available, "version" => version,
          "error" => error.to_s.empty? ? nil : error.to_s,
          "archive_sha256" => archive_sha256, "binary_sha256" => binary_sha256,
          "state" => state(available, version, error),
          "provenance" => verified?(version, binary_sha256, archive_sha256) ? "verified" : "unverified" }.compact
      end

      private

      def verified?(version, binary_sha256, archive_sha256)
        version == VERSION && binary_sha256 == BINARY_SHA256 && archive_sha256 == ARCHIVE_SHA256
      end

      def state(available, version, error)
        return "missing" if !available && error.to_s.match?(/not found|ENOENT/i)
        return "failed" unless available
        return "unsupported" unless version == VERSION

        "ready"
      end

      def execute(*command)
        output = IO.popen(command, err: [:child, :out], &:read)
        [output, "", $CHILD_STATUS.success?]
      rescue Errno::ENOENT => error
        ["", error.message, false]
      end
    end
  end
end
