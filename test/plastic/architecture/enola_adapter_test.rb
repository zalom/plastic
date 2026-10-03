# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/architecture/enola_adapter"
require "json"

module EnolaAdapterTestSupport
  private

  def snapshot(adapter, repository)
    adapter.snapshot(source: source(repository), identity: identity("unknown", nil))
  end

  def source(repository, revision: "abc", dirty: false)
    Plastic::Architecture::EnolaSnapshot::Source.new(repository:, revision:, dirty:)
  end

  def identity(binary_digest, archive_digest)
    Plastic::Architecture::EnolaProvenance::Identity.new(binary_digest:, archive_digest:)
  end

  def adapter_for(executor = nil, &block)
    command = Plastic::Architecture::EnolaCommand.new(executor: executor || block)
    Plastic::Architecture::EnolaAdapter.new(command:)
  end

  def assert_fresh_snapshot(adapter, repository)
    receipt = adapter.snapshot(source: source(repository), identity: identity(Plastic::Architecture::EnolaAdapter::BINARY_SHA256,
      Plastic::Architecture::EnolaAdapter::ARCHIVE_SHA256))

    assert_equal ["fresh", "verified"], receipt.values_at("state", "provenance")
    assert_equal %w[manifests ruby], receipt.fetch("extractors")
    assert_equal [".svg"], receipt.fetch("exclusions")
    assert_equal 12, receipt.dig("gaps", "extraction_unresolved")
  end

  def assert_top_level_quality(adapter, repository)
    receipt = snapshot(adapter, repository)

    assert_equal ["ruby", "typescript"], receipt.fetch("detected_languages")
    assert_equal [".json", ".svg"], receipt.fetch("exclusions")
    assert_equal 3, receipt.dig("gaps", "coverage_gaps")
    assert_equal 7, receipt.dig("gaps", "extraction_unresolved")
  end

  def write_snapshot(repository, commit:, dirty:, repo_path:, options: {})
    artifact_hashes = write_artifacts(repository)
    data = { "repo_path" => repo_path, "git" => { "commit" => commit, "dirty" => dirty }, "extractors" => options.fetch(:extractors, %w[manifests ruby]),
             "extractor_version" => "v265", "quality" => { "census" => { "excluded_kinds" => { ".svg" => 1 } },
                                                           "coverage" => { "extraction_unresolved" => 12 } }, "output_hashes" => artifact_hashes }
    if options[:top_level_quality]
      data["census"] = { "detected_languages" => %w[ruby typescript], "excluded_kinds" => { ".svg" => 1, ".json" => 2 } }
      data["coverage"] = { "coverage_gaps" => 3, "extraction_unresolved" => 7 }
    end
    FileUtils.mkdir_p(File.join(repository, ".enola"))
    File.write(File.join(repository, ".enola", "snapshot.meta.json"), JSON.generate(data))
  end

  def write_artifacts(repository)
    root = File.join(repository, ".enola")
    FileUtils.mkdir_p(root)
    %w[facts.jsonl llm_context.md].to_h do |name|
      path = File.join(root, name)
      File.write(path, name)
      [name, "sha256:#{Digest::SHA256.file(path).hexdigest}"]
    end
  end
end

class EnolaAdapterReceiptTest < Plastic::TestCase
  include EnolaAdapterTestSupport

  def test_marks_the_pinned_official_binary_as_verified
    adapter = adapter_for { ["enola 0.4.18", "", true] }

    receipt = adapter.receipt(identity: identity(Plastic::Architecture::EnolaAdapter::BINARY_SHA256,
      Plastic::Architecture::EnolaAdapter::ARCHIVE_SHA256))

    assert_equal "verified", receipt.fetch("provenance")
    assert_equal "0.4.18", receipt.fetch("version")
    assert_equal "enola", receipt.fetch("provider")
  end

  def test_accepts_the_pinned_executable_digest_without_an_archive_digest
    adapter = adapter_for { ["enola 0.4.18", "", true] }

    receipt = adapter.receipt(identity: identity(Plastic::Architecture::EnolaAdapter::BINARY_SHA256, nil))

    assert_equal "verified", receipt.fetch("provenance")
  end

  def test_marks_a_same_version_unknown_binary_as_unverified
    adapter = adapter_for { ["enola 0.4.18", "", true] }

    assert_equal "unverified", adapter.receipt(identity: identity("unknown", "unknown")).fetch("provenance")
  end

  def test_distinguishes_missing_unsupported_and_failed_cli_states
    missing = adapter_for { ["", "not found", false] }
    unsupported = adapter_for { ["enola 0.5.0", "", true] }
    failed = adapter_for { ["not JSON", "invalid manifest", false] }

    assert_equal "missing", missing.receipt(identity: identity("unknown", "unknown")).fetch("state")
    assert_equal "unsupported", unsupported.receipt(identity: identity("unknown", "unknown")).fetch("state")
    assert_equal "failed", failed.receipt(identity: identity("unknown", "unknown")).fetch("state")
  end
end

class EnolaAdapterSnapshotTest < Plastic::TestCase
  include EnolaAdapterTestSupport

  def test_reads_a_matching_complete_snapshot_with_coverage_and_provenance
    Dir.mktmpdir do |repository|
      write_snapshot(repository, commit: "abc", dirty: false, repo_path: repository)
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      assert_fresh_snapshot(adapter, repository)
    end
  end

  def test_reads_top_level_enola_quality_fields
    Dir.mktmpdir do |repository|
      write_snapshot(repository, commit: "abc", dirty: false, repo_path: repository, options: { top_level_quality: true })
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      assert_top_level_quality(adapter, repository)
    end
  end

  def test_marks_a_missing_snapshot
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      assert_equal "missing", adapter.snapshot(source: source(repository), identity: identity("unknown", "unknown")).fetch("state")
    end
  end

  def test_marks_invalid_snapshot_metadata
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      FileUtils.mkdir_p(File.join(repository, ".enola"))
      File.write(File.join(repository, ".enola", "snapshot.meta.json"), "bad")

      assert_equal "invalid", adapter.snapshot(source: source(repository), identity: identity("unknown", "unknown")).fetch("state")
    end
  end

  def test_marks_a_snapshot_with_an_old_revision_as_stale
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      write_snapshot(repository, commit: "old", dirty: false, repo_path: repository)

      assert_equal "stale", adapter.snapshot(source: source(repository), identity: identity("unknown", "unknown")).fetch("state")
    end
  end

  def test_marks_a_snapshot_for_another_repository_as_wrong_root
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      write_snapshot(repository, commit: "abc", dirty: false, repo_path: "/other")

      assert_equal "wrong_root", adapter.snapshot(source: source(repository), identity: identity("unknown", "unknown")).fetch("state")
    end
  end

  def test_marks_a_dirty_snapshot_as_dirty
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      write_snapshot(repository, commit: "abc", dirty: true, repo_path: repository)

      assert_equal "dirty", adapter.snapshot(source: source(repository), identity: identity("unknown", "unknown")).fetch("state")
    end
  end

  def test_marks_a_snapshot_without_extractors_as_incomplete
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      write_snapshot(repository, commit: "abc", dirty: false, repo_path: repository, options: { extractors: [] })

      assert_equal "incomplete", adapter.snapshot(source: source(repository), identity: identity("unknown", "unknown")).fetch("state")
    end
  end

  def test_preserves_an_unsupported_tool_state_when_snapshot_metadata_is_missing
    Dir.mktmpdir do |repository|
      adapter = adapter_for(->(*) { ["enola 0.5.0", "", true] })

      receipt = adapter.snapshot(source: source(repository), identity: identity("unknown", nil))

      assert_equal "unsupported", receipt.fetch("state")
      assert_equal "missing", receipt.fetch("snapshot_state")
    end
  end

  def test_marks_a_snapshot_incomplete_when_a_required_artifact_is_missing
    Dir.mktmpdir do |repository|
      write_snapshot(repository, commit: "abc", dirty: false, repo_path: repository)
      File.delete(File.join(repository, ".enola", "facts.jsonl"))
      adapter = adapter_for(->(*) { ["enola 0.4.18", "", true] })

      assert_equal "incomplete", adapter.snapshot(source: source(repository), identity: identity("unknown", nil)).fetch("state")
    end
  end
end

class EnolaAdapterRefreshTest < Plastic::TestCase
  include EnolaAdapterTestSupport

  def test_keeps_the_old_receipt_when_refresh_fails
    calls = []
    adapter = adapter_for(->(*command) {
      calls << command
      ["failed", "generation failed", false]
    })
    prior = { "state" => "fresh", "revision" => "abc" }

    result = adapter.refresh(repository: "/repo", prior:)

    refute result.fetch(:success)
    assert_equal prior, result.fetch(:receipt)
  end

  def test_calls_the_cli_for_an_explicit_refresh
    calls = []
    adapter = adapter_for(->(*command) {
      calls << command
      ["failed", "generation failed", false]
    })

    adapter.refresh(repository: "/repo", prior: nil)

    assert_equal [["enola", "--generate", "/repo"]], calls
  end

  def test_refresh_reports_failure_without_a_prior_receipt
    adapter = adapter_for(->(*) { ["failed", "generation failed", false] })

    result = adapter.refresh(repository: "/repo", prior: nil)

    refute result.fetch(:success)
    assert_nil result.fetch(:receipt)
  end
end
