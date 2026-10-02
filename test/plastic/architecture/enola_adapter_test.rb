# frozen_string_literal: true

require_relative "../../test_helper"
require "json"

class EnolaAdapterTest < Plastic::TestCase
  def test_marks_the_pinned_official_binary_as_verified
    adapter = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["enola 0.4.18", "", true] })

    receipt = adapter.receipt(binary_sha256: Plastic::Architecture::EnolaAdapter::BINARY_SHA256,
      archive_sha256: Plastic::Architecture::EnolaAdapter::ARCHIVE_SHA256)

    assert_equal "verified", receipt.fetch("provenance")
    assert_equal "0.4.18", receipt.fetch("version")
    assert_equal "enola", receipt.fetch("provider")
  end

  def test_marks_a_same_version_unknown_binary_as_unverified
    adapter = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["enola 0.4.18", "", true] })

    assert_equal "unverified", adapter.receipt(binary_sha256: "unknown", archive_sha256: "unknown").fetch("provenance")
  end

  def test_distinguishes_missing_unsupported_and_failed_cli_states
    missing = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["", "not found", false] })
    unsupported = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["enola 0.5.0", "", true] })
    failed = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["not JSON", "invalid manifest", false] })

    assert_equal "missing", missing.receipt(binary_sha256: "unknown", archive_sha256: "unknown").fetch("state")
    assert_equal "unsupported", unsupported.receipt(binary_sha256: "unknown", archive_sha256: "unknown").fetch("state")
    assert_equal "failed", failed.receipt(binary_sha256: "unknown", archive_sha256: "unknown").fetch("state")
  end

  def test_reads_a_matching_complete_snapshot_with_coverage_and_provenance
    Dir.mktmpdir do |repository|
      write_snapshot(repository, commit: "abc", dirty: false, repo_path: repository)
      adapter = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["enola 0.4.18", "", true] })
      assert_respond_to adapter, :snapshot

      receipt = adapter.snapshot(repository:, binary_sha256: Plastic::Architecture::EnolaAdapter::BINARY_SHA256,
        archive_sha256: Plastic::Architecture::EnolaAdapter::ARCHIVE_SHA256, revision: "abc", dirty: false)

      assert_equal "fresh", receipt.fetch("state")
      assert_equal "verified", receipt.fetch("provenance")
      assert_equal %w[manifests ruby], receipt.fetch("extractors")
      assert_equal [".svg"], receipt.fetch("exclusions")
      assert_equal 12, receipt.fetch("gaps").fetch("extraction_unresolved")
    end
  end

  def test_distinguishes_missing_invalid_stale_dirty_wrong_root_and_incomplete_snapshots
    Dir.mktmpdir do |repository|
      adapter = Plastic::Architecture::EnolaAdapter.new(executor: ->(*) { ["enola 0.4.18", "", true] })
      assert_respond_to adapter, :snapshot

      assert_equal "missing", adapter.snapshot(repository:, binary_sha256: "unknown", archive_sha256: "unknown", revision: "abc", dirty: false).fetch("state")
      FileUtils.mkdir_p(File.join(repository, ".enola"))
      File.write(File.join(repository, ".enola", "snapshot.meta.json"), "bad")
      assert_equal "invalid", adapter.snapshot(repository:, binary_sha256: "unknown", archive_sha256: "unknown", revision: "abc", dirty: false).fetch("state")

      write_snapshot(repository, commit: "old", dirty: false, repo_path: repository)
      assert_equal "stale", adapter.snapshot(repository:, binary_sha256: "unknown", archive_sha256: "unknown", revision: "abc", dirty: false).fetch("state")
      write_snapshot(repository, commit: "abc", dirty: false, repo_path: "/other")
      assert_equal "wrong_root", adapter.snapshot(repository:, binary_sha256: "unknown", archive_sha256: "unknown", revision: "abc", dirty: false).fetch("state")
      write_snapshot(repository, commit: "abc", dirty: true, repo_path: repository)
      assert_equal "dirty", adapter.snapshot(repository:, binary_sha256: "unknown", archive_sha256: "unknown", revision: "abc", dirty: false).fetch("state")
      write_snapshot(repository, commit: "abc", dirty: false, repo_path: repository, extractors: [])
      assert_equal "incomplete", adapter.snapshot(repository:, binary_sha256: "unknown", archive_sha256: "unknown", revision: "abc", dirty: false).fetch("state")
    end
  end

  def test_refresh_calls_the_cli_only_when_requested_and_keeps_the_old_receipt_on_failure
    calls = []
    adapter = Plastic::Architecture::EnolaAdapter.new(executor: ->(*command) { calls << command; ["failed", "generation failed", false] })
    prior = { "state" => "fresh", "revision" => "abc" }
    assert_respond_to adapter, :refresh

    assert_equal prior, adapter.refresh(repository: "/repo", prior:)
    assert_equal [["enola", "--generate", "/repo"]], calls
  end

  private

  def write_snapshot(repository, commit:, dirty:, repo_path:, extractors: %w[manifests ruby])
    data = { "repo_path" => repo_path, "git" => { "commit" => commit, "dirty" => dirty }, "extractors" => extractors,
             "extractor_version" => "v265", "quality" => { "census" => { "excluded_kinds" => { ".svg" => 1 } },
                                                           "coverage" => { "extraction_unresolved" => 12 } } }
    FileUtils.mkdir_p(File.join(repository, ".enola"))
    File.write(File.join(repository, ".enola", "snapshot.meta.json"), JSON.generate(data))
  end
end
