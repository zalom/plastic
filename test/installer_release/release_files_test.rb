# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseFilesTest < Minitest::Test
  include ReleaseHelper

  def test_verifies_the_archive_against_its_checksum_file
    files = InstallerRelease::ReleaseFiles.new(release_files)

    assert_same files, files.verify
    assert_equal "2.0.3", files.manifest.dig("release", "version")
    assert_equal "plastic.tgz", File.basename(files.archive)
  end

  def test_accepts_the_binary_marker_of_the_checksum_line
    directory = release_files
    checksum = File.join(directory, "plastic.tgz.sha256")
    File.write(checksum, File.read(checksum).sub("  plastic.tgz", " *plastic.tgz"))

    assert InstallerRelease::ReleaseFiles.new(directory).verify
  end

  def test_rejects_an_archive_that_does_not_match_its_checksum
    directory = release_files
    File.binwrite(File.join(directory, "plastic.tgz"), "corrupt")

    assert_equal "archive checksum does not match", problem(directory)
  end

  def test_rejects_a_checksum_file_for_another_archive
    directory = release_files
    File.write(File.join(directory, "plastic.tgz.sha256"), "#{"0" * 64}  other.tgz\n")

    assert_equal "checksum file does not name plastic.tgz", problem(directory)
  end

  def test_names_a_missing_release_file
    directory = release_files
    File.delete(File.join(directory, "plastic.tgz.sha256"))

    assert_equal "release is missing plastic.tgz.sha256", problem(directory)
  end

  def test_rejects_a_manifest_that_does_not_parse
    directory = release_files
    File.write(File.join(directory, "plastic.manifest.json"), "{")

    error = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::ReleaseFiles.new(directory).manifest }
    assert_equal "manifest does not parse", error.message
  end

  def test_digests_through_the_injected_digest
    digest = Struct.new(:hexdigest) { def file(_path) = self }.new("f" * 64)
    directory = release_files
    File.write(File.join(directory, "plastic.tgz.sha256"), "#{"f" * 64}  plastic.tgz\n")

    assert InstallerRelease::ReleaseFiles.new(directory, digest: digest).verify
  end

  private

  def problem(directory)
    error = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::ReleaseFiles.new(directory).verify }
    error.message
  end
end
