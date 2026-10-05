# frozen_string_literal: true

require "digest"
require_relative "release_helper"

class InstallerReleaseManifestTest < Minitest::Test
  include ReleaseHelper

  def setup
    super
    @archive = archive_with
    @manifest = manifest_for(@archive)
  end

  def test_binds_the_archive_to_its_release_identity
    assert InstallerRelease::Manifest.check(@manifest, archive: @archive, expected_release: release)
    assert_equal Digest::SHA256.file(@archive).hexdigest, @manifest.dig("archive", "sha256")
  end

  def test_writes_the_manifest_as_json
    path = File.join(@root, "plastic.manifest.json")
    InstallerRelease::Manifest.write(path, archive: @archive, release: release)

    assert_equal @manifest, JSON.parse(File.read(path))
  end

  def test_rejects_a_mismatched_archive
    File.binwrite(@archive, "corrupt archive")

    assert_equal "archive checksum does not match", problem(@manifest)
  end

  def test_rejects_a_renamed_archive
    assert_equal "archive name does not match", problem(@manifest.merge("archive" => { "name" => "x.tgz", "sha256" => "" }))
  end

  def test_rejects_missing_and_malformed_sections
    assert_equal "manifest is missing ruby", problem(@manifest.except("ruby"))
    assert_equal "archive is not an object", problem(@manifest.merge("archive" => []))
  end

  def test_rejects_an_unexpected_release_identity
    assert_equal "release channel does not match", problem(@manifest, release.merge("channel" => "alpha"))
    assert_equal "release tag does not match version", problem(with_release("tag" => "v9.9.9"), {})
    assert_equal "release repository is not official HTTPS", problem(with_release("repository" => "http://x"), {})
  end

  def test_names_the_identity_of_a_version_with_its_channel
    assert_equal({ "tag" => "v2.0.3", "version" => "2.0.3", "channel" => "latest" }, InstallerRelease::Manifest.identity("2.0.3"))
    assert_equal "alpha", InstallerRelease::Manifest.identity("2.1.0-alpha.4").fetch("channel")
    assert_equal "beta", InstallerRelease::Manifest.identity("2.1.0-beta.1").fetch("channel")
  end

  private

  def with_release(changes) = @manifest.merge("release" => @manifest.fetch("release").merge(changes))

  def problem(manifest, expected = release)
    error = assert_raises(InstallerRelease::VerificationError) do
      InstallerRelease::Manifest.check(manifest, archive: @archive, expected_release: expected)
    end
    error.message
  end
end
