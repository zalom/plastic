# frozen_string_literal: true

require "json"

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

      def snapshot(repository:, binary_sha256:, archive_sha256:, revision:, dirty:)
        base = receipt(binary_sha256:, archive_sha256:)
        metadata = read_metadata(repository)
        return base.merge("state" => metadata) if metadata.is_a?(String)

        base.merge(snapshot_fields(metadata)).merge("revision" => metadata.dig("git", "commit"),
          "state" => snapshot_state(base, metadata, repository:, revision:, dirty:))
      end

      def refresh(repository:, prior:)
        _output, _error, successful = @executor.call("enola", "--generate", repository)
        successful ? nil : prior
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

      def read_metadata(repository)
        JSON.parse(File.read(File.join(repository, ".enola", "snapshot.meta.json")))
      rescue Errno::ENOENT
        "missing"
      rescue JSON::ParserError
        "invalid"
      end

      def snapshot_fields(metadata)
        quality = metadata.fetch("quality", {})
        census = quality.fetch("census", {})
        coverage = quality.fetch("coverage", {})
        { "repository" => metadata["repo_path"], "extractor_version" => metadata["extractor_version"],
          "extractors" => metadata.fetch("extractors", []), "manifest" => metadata["snapshot_id"],
          "manifest_hash" => metadata["config_hash"], "detected_languages" => metadata.fetch("extractors", []),
          "exclusions" => census.fetch("excluded_kinds", {}).keys.sort,
          "gaps" => { "coverage_gaps" => coverage["coverage_gaps"],
                      "unresolved_edges" => coverage["unresolved_edges"],
                      "extraction_unresolved" => coverage["extraction_unresolved"] } }
      end

      def snapshot_state(base, metadata, repository:, revision:, dirty:)
        return base.fetch("state") unless base.fetch("state") == "ready"
        mismatch = snapshot_mismatch(metadata, repository:, revision:, dirty:)
        return mismatch if mismatch
        return "incomplete" if metadata.fetch("extractors", []).empty? || metadata["extractor_version"].to_s.empty?

        "fresh"
      end

      def snapshot_mismatch(metadata, repository:, revision:, dirty:)
        return "wrong_root" unless same_repository?(metadata.fetch("repo_path", ""), repository)
        return "stale" unless metadata.dig("git", "commit") == revision
        "dirty" if dirty != metadata.dig("git", "dirty")
      end

      def same_repository?(recorded, repository)
        File.realpath(recorded) == File.realpath(repository)
      rescue Errno::ENOENT
        false
      end

      def execute(*command)
        output = IO.popen(command, err: [:child, :out], &:read)
        [output, "", $?.success?]
      rescue Errno::ENOENT => error
        ["", error.message, false]
      end
    end
  end
end
