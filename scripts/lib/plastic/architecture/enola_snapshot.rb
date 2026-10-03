# frozen_string_literal: true

require "digest"
require "json"

module Plastic
  module Architecture
    # Validates the Enola artifacts against the source state they describe.
    class EnolaSnapshot
      Source = Data.define(:repository, :revision, :dirty)

      def initialize(provenance:)
        @provenance = provenance
      end

      def receipt(source:, identity:)
        base = @provenance.receipt(identity)
        metadata = Metadata.read(source.repository)
        return unavailable_snapshot(base, metadata) if metadata.is_a?(String)

        metadata.receipt(base).merge("revision" => metadata.revision, "state" => metadata.state(base, source))
      end

      private

      def unavailable_snapshot(base, snapshot_state)
        state = (base.fetch("state") == "ready") ? snapshot_state : base.fetch("state")
        base.merge("snapshot_state" => snapshot_state, "state" => state)
      end
    end

    # The `.enola` manifest and artifacts belong together as one snapshot.
    class EnolaSnapshot::Metadata
      REQUIRED_ARTIFACTS = %w[facts.jsonl llm_context.md].freeze

      def self.read(repository)
        new(JSON.parse(File.read(File.join(repository, ".enola", "snapshot.meta.json"))), repository)
      rescue Errno::ENOENT
        "missing"
      rescue JSON::ParserError
        "invalid"
      end

      def initialize(data, repository)
        @data = data
        @repository = repository
      end

      def receipt(base)
        base.merge(identity).merge(quality)
      end

      def revision = @data.dig("git", "commit")

      def state(base, source)
        return base.fetch("state") unless base.fetch("state") == "ready"
        return mismatch(source) if mismatch(source)
        return "incomplete" unless complete?

        "fresh"
      end

      private

      def identity
        { "repository" => @data["repo_path"], "extractor_version" => @data["extractor_version"],
          "extractors" => @data.fetch("extractors", []), "manifest" => @data["snapshot_id"],
          "manifest_hash" => @data["config_hash"] }
      end

      def quality
        source = @data.fetch("quality", {})
        census = @data.fetch("census", source.fetch("census", {}))
        coverage = @data.fetch("coverage", source.fetch("coverage", {}))
        { "detected_languages" => census.fetch("detected_languages", @data.fetch("extractors", [])).sort,
          "exclusions" => census.fetch("excluded_kinds", {}).keys.sort,
          "gaps" => coverage.slice("coverage_gaps", "unresolved_edges", "extraction_unresolved") }
      end

      def mismatch(source)
        return "wrong_root" unless same_repository?(@data.fetch("repo_path", ""), source.repository)
        return "stale" unless revision == source.revision

        "dirty" if source.dirty != @data.dig("git", "dirty")
      end

      def complete?
        @data.fetch("extractors", []).any? && !@data["extractor_version"].to_s.empty? && artifacts_valid?
      end

      def artifacts_valid?
        hashes = @data.fetch("output_hashes", {})
        REQUIRED_ARTIFACTS.all? { |name| hash_matches?(hashes.fetch(name, ""), File.join(@repository, ".enola", name)) }
      end

      def hash_matches?(expected, path)
        expected == "sha256:#{Digest::SHA256.file(path).hexdigest}"
      rescue Errno::ENOENT
        false
      end

      def same_repository?(recorded, repository)
        File.realpath(recorded) == File.realpath(repository)
      rescue Errno::ENOENT
        false
      end
    end
  end
end
