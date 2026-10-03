# frozen_string_literal: true

module Plastic
  module Architecture
    # Identifies the tested upstream Enola release that produced a receipt.
    class EnolaProvenance
      VERSION = "0.4.18"
      ARCHIVE_SHA256 = "d31f197bb86ea1eebaa2caa2434e039bf47516daad5455ca400bcfd37923f837"
      BINARY_SHA256 = "9f04b4637e22eac056a85959b20ec68ebe7311b42c20e2b02bd5dfe50edb0f21"

      # Records the checksums that identify the local Enola release.
      Identity = Data.define(:binary_digest, :archive_digest) do
        def verified_for?(version)
          version == VERSION && (binary_digest == BINARY_SHA256 || archive_digest == ARCHIVE_SHA256)
        end
      end

      # Captures the observable result of asking Enola for its version.
      Tool = Data.define(:available, :version, :error) do
        def state
          return "missing" if !available && error.to_s.match?(/not found|ENOENT/i)
          return "failed" unless available
          return "unsupported" unless version == VERSION

          "ready"
        end
      end

      def initialize(command: EnolaCommand.new)
        @command = command
      end

      def receipt(identity)
        tool = @command.version
        { "provider" => "enola", "available" => tool.available, "version" => tool.version,
          "error" => tool.error, "archive_sha256" => identity.archive_digest,
          "binary_sha256" => identity.binary_digest, "state" => tool.state,
          "provenance" => identity.verified_for?(tool.version) ? "verified" : "unverified" }.compact
      end

      def refresh(repository)
        @command.generate(repository)
      end
    end

    # Runs Enola through its public command-line interface.
    class EnolaCommand
      def initialize(executor: method(:execute))
        @executor = executor
      end

      def version
        output, error, available = @executor.call("enola", "--version")
        EnolaProvenance::Tool.new(available:, version: output.to_s[/\d+\.\d+\.\d+/], error: error.to_s.empty? ? nil : error.to_s)
      end

      def generate(repository)
        _output, _error, successful = @executor.call("enola", "--generate", repository)
        successful
      end

      private

      def execute(*command)
        output = IO.popen(command, err: [:child, :out], &:read)
        [output, "", $?.success?]
      rescue Errno::ENOENT => error
        ["", error.message, false]
      end
    end
  end
end
