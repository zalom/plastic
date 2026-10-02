# frozen_string_literal: true

require_relative "../../test_helper"

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
end
